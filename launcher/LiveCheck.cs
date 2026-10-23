// Opt-in operator integration probe. Never included in the tester launcher.
using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Security.Principal;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace AetheriaLauncher {
internal static class LiveCheck {
    sealed class ProbeRpc : IButlerRpc {
        readonly IButlerRpc inner;
        public ProbeRpc(IButlerRpc value) {inner=value;}
        public async Task<Dictionary<string,object>> Call(string method,object args,int timeout) {
            try {return await inner.Call(method,args,timeout);}
            catch {Console.WriteLine("Failed daemon operation: "+method);throw;}
        }
    }
    static string PipeName {get {return "AetheriaLauncherLive-"+WindowsIdentity.GetCurrent().User.Value;}}
    static string Root {get {return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Aetheria","online","beta-runtime");}}
    [STAThread] public static int Main(string[] args) {
        if(args.Length==1 && OAuthFlow.IsCallback(args[0])) return CallbackPipe.Send(PipeName,args[0]) ? 0 : 1;
        try { Run(args).GetAwaiter().GetResult();return 0; }
        catch(Exception ex) {Console.WriteLine("Live validation failed: "+ex.Message);return 1;}
    }
    static async Task Run(string[] args) {
        string state=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Aetheria","launcher");
        var config=LauncherConfig.Load(Path.Combine(Root,"launcher.json"));
        using(var daemon=new ButlerDaemon()) {
            await daemon.Start(Path.Combine(Root,"butler","butler.exe"),state);
            if(args.Length==1 && args[0]=="--oauth") {
                var flow=new OAuthFlow();var callback=new TaskCompletionSource<string>();
                using(var pipe=new CallbackPipe(PipeName)) {
                    pipe.Received+=value=>callback.TrySetResult(value);pipe.Start();
                    string key=@"Software\Classes\aetheria-launcher\shell\open\command";
                    object previous=null;
                    using(var existing=Registry.CurrentUser.OpenSubKey(key)) if(existing!=null)previous=existing.GetValue("");
                    try {
                        using(var protocol=Registry.CurrentUser.CreateSubKey(@"Software\Classes\aetheria-launcher")) {
                            protocol.SetValue("","URL:Aetheria Launcher OAuth");protocol.SetValue("URL Protocol","");
                            using(var command=protocol.CreateSubKey(@"shell\open\command"))command.SetValue("","\""+Process.GetCurrentProcess().MainModule.FileName+"\" \"%1\"");
                        }
                        File.WriteAllText(Path.Combine(Root,"consumer-oauth-url.txt"),flow.Begin(config.OAuthClientId));
                        Console.WriteLine("Consumer PKCE request prepared; waiting for browser callback.");
                        if(await Task.WhenAny(callback.Task,Task.Delay(TimeSpan.FromMinutes(10)))!=callback.Task)throw new Exception("OAuth callback timed out.");
                        var login=await daemon.Rpc.Call("Profile.LoginWithOAuthCode",flow.Accept(await callback.Task),15000);
                        long id=Json.Number(Json.Object(login,"profile"),"id");
                        if(id<=0)throw new Exception("No consumer profile returned.");
                        await daemon.Rpc.Call("Fetch.ProfileOwnedKeys",new {profileId=id,fresh=true,limit=1},15000);
                        var owned=await daemon.Rpc.Call("Fetch.GameOwnership",new {profileId=id,gameId=config.GameId},5000);
                        if(!Json.Flag(owned,"owned") || Json.Text(owned,"source")!="download_key" || Json.Number(owned,"downloadKeyId")<=0)throw new Exception("Claimed invitation ownership was not verified.");
                        File.WriteAllText(Path.Combine(state,"profile-id.txt"),id.ToString());
                        Console.WriteLine("PASS: real consumer PKCE exchange, saved login, fresh claimed invitation ownership.");
                    } finally {
                        flow.Cancel();File.Delete(Path.Combine(Root,"consumer-oauth-url.txt"));
                        using(var command=Registry.CurrentUser.CreateSubKey(key)) {
                            string launcher=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Aetheria","launcher-app","AetheriaLauncher.exe");
                            command.SetValue("",previous ?? ("\""+launcher+"\" \"%1\""));
                        }
                    }
                }
            } else {
                var service=new LauncherService(config,state,new ProbeRpc(daemon.Rpc),new HttpsReleaseSource(config.AccountUrl));
                bool updating=args.Length==1 && args[0]=="--update";
                try {await service.Initialize();}
                catch(LauncherException) {if(!updating)throw;}
                // The UI permits Check / update after an uninstalled or outdated
                // startup. Update repeats ownership, release and integrity gates.
                if(updating)await service.Update();
                if(!service.Ready)throw new Exception("The current release is not ready.");
                Console.WriteLine("PASS: real selected-account access, HTTPS release preflight, installed EXE hash and version.");
                if(args.Length==1 && args[0]=="--play") {
                    await service.Play();
                    if(!service.GameRunning)throw new Exception("The game process did not start.");
                    Console.WriteLine("PASS: real tester EXE launched through the release gate.");
                }
            }
        }
    }
}
}
