using System;
using System.IO;
using System.IO.Pipes;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Diagnostics;
using System.Windows.Forms;
using Microsoft.Win32;

namespace AetheriaLauncher {
internal sealed class CallbackPipe : IDisposable {
    readonly string name; readonly SecurityIdentifier user; bool stopped; NamedPipeServerStream current;
    public event Action<string> Received;
    public CallbackPipe(string pipeName) {name=pipeName;user=WindowsIdentity.GetCurrent().User;}
    public void Start() {ThreadPool.QueueUserWorkItem(delegate {Listen();});}
    void Listen() {
        while(!stopped) {
            try {
                var acl=new PipeSecurity(); acl.SetAccessRuleProtection(true,false); acl.SetOwner(user); acl.AddAccessRule(new PipeAccessRule(user,PipeAccessRights.FullControl,AccessControlType.Allow));
                using(var pipe=new NamedPipeServerStream(name,PipeDirection.In,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,8192,8192,acl)) {
                    current=pipe; pipe.WaitForConnection();
                    // Close slow clients after two seconds; callbacks are a single bounded UTF-8 URI.
                    var read=Task.Run(delegate {
                        using(var reader=new BinaryReader(pipe,System.Text.Encoding.UTF8,true)) {
                            int size=reader.ReadInt32(); if(size<1 || size>8192) return;
                            byte[] bytes=reader.ReadBytes(size); if(bytes.Length!=size) return;
                            string uri=new System.Text.UTF8Encoding(false,true).GetString(bytes);
                            if(OAuthFlow.IsCallback(uri)) {var handler=Received;if(handler!=null) handler(uri);}
                        }
                    });
                    try {read.Wait(2000);} catch {} pipe.Dispose();
                }
            } catch {if(stopped)return;} finally {current=null;}
        }
    }
    public static bool Send(string pipeName,string uri) {
        try {using(var pipe=new NamedPipeClientStream(".",pipeName,PipeDirection.Out)) {
            pipe.Connect(2000); using(var writer=new BinaryWriter(pipe,System.Text.Encoding.UTF8,true)) {byte[] bytes=System.Text.Encoding.UTF8.GetBytes(uri); if(bytes.Length>8192)return false;writer.Write(bytes.Length);writer.Write(bytes);writer.Flush();} return true;
        }} catch {return false;}
    }
    public void Dispose() {stopped=true;var pipe=current;if(pipe!=null)try {pipe.Dispose();}catch {}}
}
internal static class Program {
    [STAThread] public static int Main(string[] args) {
        System.Net.ServicePointManager.SecurityProtocol=System.Net.SecurityProtocolType.Tls12;
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        string sid=WindowsIdentity.GetCurrent().User.Value, name="AetheriaLauncher-"+sid;
        if(args.Length>0) {
            if(args.Length==1 && OAuthFlow.IsCallback(args[0]) && CallbackPipe.Send(name,args[0])) return 0;
            MessageBox.Show("Return to the launcher and choose Sign in to itch.io again.","Aetheria Launcher",MessageBoxButtons.OK,MessageBoxIcon.Information); return 1;
        }
        bool created; var security=new MutexSecurity();security.SetAccessRuleProtection(true,false);security.AddAccessRule(new MutexAccessRule(new SecurityIdentifier(sid),MutexRights.FullControl,AccessControlType.Allow));
        using(var single=new Mutex(true,"Local\\"+name,out created,security)) {
            if(!created) {MessageBox.Show("Aetheria Launcher is already open.","Aetheria Launcher");return 0;}
            using(var pipe=new CallbackPipe(name)) using(var form=new LauncherForm()) {
                pipe.Received+=form.ReceiveCallback; pipe.Start(); Application.Run(form);
            }
            single.ReleaseMutex();
        }
        return 0;
    }
}
internal sealed class LauncherForm : Form {
    readonly Label status=new Label(),version=new Label(); readonly Button sign=new Button(),update=new Button(),play=new Button(); readonly ProgressBar progress=new ProgressBar();
    readonly ButlerDaemon daemon=new ButlerDaemon(); readonly OAuthFlow oauth=new OAuthFlow();
    readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
    LauncherConfig config; LauncherService service; bool busy,loggingIn,closing,started; TaskCompletionSource<string> callback;
    public LauncherForm() {
        Text="Aetheria Launcher"; ClientSize=new Size(540,285); MinimumSize=new Size(556,324);MaximumSize=new Size(556,324); StartPosition=FormStartPosition.CenterScreen; FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;
        BackColor=Color.FromArgb(24,31,44);ForeColor=Color.FromArgb(233,235,240);Font=new Font("Segoe UI",10);
        var title=new Label {Text="AETHERIA",Font=new Font("Segoe UI",23,FontStyle.Bold),Location=new Point(26,20),AutoSize=true};Controls.Add(title);
        version.SetBounds(28,73,485,25);version.Text="Launcher 1.0 • Windows beta";Controls.Add(version);
        status.SetBounds(28,107,480,62);status.Text="Connecting to the beta service…";Controls.Add(status);
        progress.SetBounds(28,177,482,16);progress.Minimum=0;progress.Maximum=100;Controls.Add(progress);
        sign.SetBounds(28,213,192,39);sign.Text="Sign in to itch.io";update.SetBounds(232,213,155,39);update.Text="Check / update";play.SetBounds(399,213,111,39);play.Text="Play";
        foreach(var button in new []{sign,update,play}) {button.FlatStyle=FlatStyle.Flat;button.BackColor=Color.FromArgb(43,64,85);button.ForeColor=ForeColor;Controls.Add(button);button.Enabled=false;}
        sign.Click+=async (sender,e)=> {if(loggingIn) {oauth.Cancel();if(callback!=null)callback.TrySetCanceled();return;} await Login();};
        update.Click+=async (sender,e)=> {await Run(async delegate {if(!started) await Startup();else {await service.Update();status.Text="The current beta is ready to play.";}});};
        play.Click+=async (sender,e)=> {await Run(async delegate {await service.Play();status.Text="Aetheria is running. Close the game before updating.";});};
        Shown+=async (sender,e)=> {await Run(Startup);};
        FormClosing+=(sender,e)=> {closing=true;oauth.Cancel();if(callback!=null)callback.TrySetCanceled();timer.Stop();daemon.Dispose();};
        timer.Interval=1000;timer.Tick+=(sender,e)=> {if(!busy && service!=null && !service.GameRunning) UpdateButtons();};timer.Start();
    }
    async Task Startup() {
        config=LauncherConfig.Load(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"launcher.json"));
        string state=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Aetheria","launcher");
        // Startup always contacts the trusted release endpoint before enabling any game action.
        var source=new HttpsReleaseSource(config.AccountUrl); await source.Get();
        await daemon.Start(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"butler.exe"),state);
        daemon.Rpc.Notification+=(method,data)=> {if(method=="Progress" && !closing && IsHandleCreated) BeginInvoke((Action)delegate {object number;if(data!=null && data.TryGetValue("progress",out number)) {double amount; if(Double.TryParse(Convert.ToString(number,System.Globalization.CultureInfo.InvariantCulture),System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out amount) && !Double.IsNaN(amount))progress.Value=(int)Math.Max(0,Math.Min(100,amount*100));}});};
        service=new LauncherService(config,state,daemon.Rpc,source);started=true;
        await service.Initialize();status.Text="The current beta is ready to play.";
    }
    void UpdateButtons() {
        sign.Enabled=config!=null && started && (!busy || loggingIn);update.Enabled=!busy;play.Enabled=!busy && service!=null && service.Ready && !service.GameRunning;
        if(service!=null)version.Text="Launcher 1.0 • "+service.Version;
    }
    async Task Run(Func<Task> action) {
        if(busy || closing)return;busy=true;if(service!=null)service.Invalidate();progress.Value=0;UpdateButtons();
        try {await action();}
        catch(LauncherException ex) {status.Text=ex.Message;}
        catch {status.Text="The launcher could not complete this action. Please retry, or extract a fresh launcher download.";}
        finally {busy=false;if(!closing)UpdateButtons();}
    }
    async Task Login() {
        await Run(async delegate {
            loggingIn=true;callback=new TaskCompletionSource<string>();sign.Text="Cancel sign-in";UpdateButtons();
            try {
                using(var protocol=Registry.CurrentUser.CreateSubKey(@"Software\Classes\aetheria-launcher")) {protocol.SetValue("", "URL:Aetheria Launcher OAuth");protocol.SetValue("URL Protocol","");using(var command=protocol.CreateSubKey(@"shell\open\command"))command.SetValue("","\""+Application.ExecutablePath+"\" \"%1\"");}
                string url=oauth.Begin(config.OAuthClientId);Process.Start(new ProcessStartInfo(url) {UseShellExecute=true});status.Text="Finish signing in in your browser. You can cancel here.";
                if(await Task.WhenAny(callback.Task,Task.Delay(TimeSpan.FromMinutes(10)))!=callback.Task) throw new LauncherException("Sign-in timed out. Please sign in again.");
                string value;try {value=await callback.Task;}catch(TaskCanceledException){throw new LauncherException("Sign-in cancelled. Choose Sign in to itch.io to retry.");}
                await service.Login(oauth.Accept(value));status.Text=service.Ready ? "The current beta is ready to play." : "Signed in. Choose Check / update to install Aetheria.";
            } finally {oauth.Cancel();callback=null;loggingIn=false;sign.Text="Sign in to itch.io";}
        });
    }
    public void ReceiveCallback(string uri) {
        if(closing || !IsHandleCreated)return;
        BeginInvoke((Action)delegate {if(loggingIn && callback!=null)callback.TrySetResult(uri);});
    }
}
}
