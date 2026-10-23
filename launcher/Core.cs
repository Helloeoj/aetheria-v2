using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Web;
using System.Web.Script.Serialization;

namespace AetheriaLauncher {
internal sealed class LauncherException : Exception { public LauncherException(string message) : base(message) {} }
internal static class Json {
    public static Dictionary<string,object> Parse(string text) { return new JavaScriptSerializer { MaxJsonLength=4*1024*1024, RecursionLimit=48 }.Deserialize<Dictionary<string,object>>(text); }
    public static string Stringify(object value) { return new JavaScriptSerializer { MaxJsonLength=4*1024*1024 }.Serialize(value); }
    public static string Text(Dictionary<string,object> value,string key) { object item; return value!=null && value.TryGetValue(key,out item) && item is string ? (string)item : ""; }
    public static long Number(Dictionary<string,object> value,string key) { object item; if(value==null || !value.TryGetValue(key,out item) || !(item is int || item is long)) return 0; return Convert.ToInt64(item); }
    public static bool Flag(Dictionary<string,object> value,string key) { object item; return value!=null && value.TryGetValue(key,out item) && item is bool && (bool)item; }
    public static Dictionary<string,object> Object(Dictionary<string,object> value,string key) { object item; return value!=null && value.TryGetValue(key,out item) ? item as Dictionary<string,object> : null; }
    public static object[] Array(Dictionary<string,object> value,string key) { object item; if(value==null || !value.TryGetValue(key,out item))return new object[0]; var list=item as System.Collections.IList; if(list==null)return new object[0]; var result=new object[list.Count];list.CopyTo(result,0);return result; }
    public static string ReadSmall(string path) { using(var stream=File.OpenRead(path)) { if(stream.Length>65536) throw new LauncherException("The release information is invalid. Please check for updates."); using(var reader=new StreamReader(stream,Encoding.UTF8,true)) return reader.ReadToEnd(); } }
    public static string ReadLine(TextReader reader,int limit) { var value=new StringBuilder(); int c; while((c=reader.Read())!=-1) { if(c=='\n') return value.ToString().TrimEnd('\r'); if(value.Length>=limit) throw new IOException("Message too large"); value.Append((char)c); } return value.Length==0 ? null : value.ToString(); }
}
internal sealed class LauncherConfig {
    public int GameId, UploadId; public string OAuthClientId, AccountUrl;
    public const string Executable="Aetheria.exe";
    public static LauncherConfig Load(string path) {
        var data=Json.Parse(Json.ReadSmall(path)); Uri uri;
        if(Json.Number(data,"schema")!=1 || Json.Text(data,"executable")!=Executable || Json.Number(data,"download_bytes_per_second")!=500000)
            throw new LauncherException("This launcher's settings are invalid. Please download a fresh launcher.");
        string account=Json.Text(data,"account_url").TrimEnd('/');
        if(!Uri.TryCreate(account,UriKind.Absolute,out uri) || uri.Scheme!="https" || uri.UserInfo!="" || uri.Query!="" || uri.Fragment!="")
            throw new LauncherException("The account service address is invalid. Please download a fresh launcher.");
        long game=Json.Number(data,"game_id"),upload=Json.Number(data,"upload_id");
        if(game<=0 || game>int.MaxValue || upload<=0 || upload>int.MaxValue || String.IsNullOrWhiteSpace(Json.Text(data,"oauth_client_id")))
            throw new LauncherException("The beta launcher is awaiting its itch.io setup. Please try the next launcher release.");
        return new LauncherConfig { GameId=(int)game, UploadId=(int)upload, OAuthClientId=Json.Text(data,"oauth_client_id"), AccountUrl=account };
    }
}
internal static class SafePath {
    public static string Within(string root,string candidate) {
        string basePath=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        string path=Path.GetFullPath(candidate);
        if(!path.StartsWith(basePath,StringComparison.OrdinalIgnoreCase)) throw new LauncherException("The installed game folder is invalid. Please check for updates.");
        DemandNoReparse(path); return path;
    }
    public static void DemandNoReparse(string path) {
        string current=Path.GetFullPath(path);
        while(!String.IsNullOrEmpty(current)) {
            if((File.Exists(current)||Directory.Exists(current)) && (File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)
                throw new LauncherException("The game folder contains a redirected path. Please restore the game folder and retry.");
            current=Path.GetDirectoryName(current);
        }
    }
}
internal static class ReleaseGate {
    public static void Validate(Dictionary<string,object> release) {
        string hash=Json.Text(release,"client_sha256");
        if(!Json.Flag(release,"ok") || !Json.Flag(release,"enabled")) throw new LauncherException("The beta is unavailable right now. Please retry later.");
        if(String.IsNullOrWhiteSpace(Json.Text(release,"release_id")) || Json.Text(release,"release_id").Length>200 || Json.Number(release,"client_bytes")<=0 || hash.Length!=64)
            throw new LauncherException("The service returned incomplete release information. Please retry later.");
        foreach(char c in hash) if(!Uri.IsHexDigit(c)) throw new LauncherException("The service returned invalid release information. Please retry later.");
    }
    public static string Verify(string root,string folder,Dictionary<string,object> release,bool interrupted) {
        Validate(release);
        if(interrupted) throw new LauncherException("The previous update did not finish. Choose Check / update to repair it.");
        folder=SafePath.Within(root,folder);
        string exe=SafePath.Within(folder,Path.Combine(folder,LauncherConfig.Executable));
        string manifest=SafePath.Within(folder,Path.Combine(folder,"release.json"));
        if(!File.Exists(exe)||!File.Exists(manifest)) throw new LauncherException("The game needs to be installed or repaired. Choose Check / update.");
        var installed=Json.Parse(Json.ReadSmall(manifest));
        if(Json.Number(installed,"schema")!=1 || Json.Text(installed,"executable")!=LauncherConfig.Executable || Json.Text(installed,"release_id")!=Json.Text(release,"release_id"))
            throw new LauncherException("A new beta release is required. Choose Check / update.");
        using(var file=new FileStream(exe,FileMode.Open,FileAccess.Read,FileShare.Read)) using(var sha=SHA256.Create()) {
            if(file.Length!=Json.Number(release,"client_bytes") || BitConverter.ToString(sha.ComputeHash(file)).Replace("-","").ToLowerInvariant()!=Json.Text(release,"client_sha256").ToLowerInvariant())
                throw new LauncherException("The game does not match the current beta release. Choose Check / update to repair it.");
        }
        return exe;
    }
}
internal interface IReleaseSource { Task<Dictionary<string,object>> Get(); }
internal sealed class HttpsReleaseSource : IReleaseSource {
    readonly string url;
    public HttpsReleaseSource(string accountUrl) { url=accountUrl.TrimEnd('/')+"/api/release"; }
    public Task<Dictionary<string,object>> Get() {
        return Task.Run(delegate {
            try {
                var uri=new Uri(url); if(uri.Scheme!="https" || uri.UserInfo!="") throw new IOException();
                var request=(HttpWebRequest)WebRequest.Create(uri); request.Method="GET"; request.Timeout=10000; request.ReadWriteTimeout=10000; request.AllowAutoRedirect=false; request.UserAgent="AetheriaLauncher/1"; request.CachePolicy=new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
                using(var deadline=new System.Threading.Timer(delegate {request.Abort();},null,10000,Timeout.Infinite))
                using(var response=(HttpWebResponse)request.GetResponse()) {
                    if(response.StatusCode!=HttpStatusCode.OK || response.ContentLength>65536) throw new IOException();
                    using(var stream=response.GetResponseStream()) using(var result=new MemoryStream()) {
                        var bytes=new byte[4096]; int length; while((length=stream.Read(bytes,0,bytes.Length))>0) { if(result.Length+length>65536) throw new IOException(); result.Write(bytes,0,length); }
                        var data=Json.Parse(Encoding.UTF8.GetString(result.ToArray())); ReleaseGate.Validate(data); return data;
                    }
                }
            } catch(LauncherException) { throw; } catch { throw new LauncherException("The beta service could not be reached securely. Check your connection and retry."); }
        });
    }
}
internal sealed class OAuthFlow {
    public const string RedirectUri="aetheria-launcher://oauth-callback";
    public string State {get;private set;}
    string verifier,clientId; DateTime expires; bool pending;
    static string RandomToken() { byte[] data=new byte[32]; using(var rng=RandomNumberGenerator.Create()) rng.GetBytes(data); return Base64(data); }
    static string Base64(byte[] data) { return Convert.ToBase64String(data).TrimEnd('=').Replace('+','-').Replace('/','_'); }
    public string Begin(string id) {
        State=RandomToken(); verifier=RandomToken(); clientId=id; expires=DateTime.UtcNow.AddMinutes(10); pending=true;
        string challenge; using(var hash=SHA256.Create()) challenge=Base64(hash.ComputeHash(Encoding.ASCII.GetBytes(verifier)));
        return "https://itch.io/user/oauth?client_id="+Uri.EscapeDataString(id)+"&scope="+Uri.EscapeDataString("profile:me profile:owned game:view:uploads")+"&redirect_uri="+Uri.EscapeDataString(RedirectUri)+"&response_type=code&state="+State+"&code_challenge="+challenge+"&code_challenge_method=S256";
    }
    public void Cancel() { pending=false; verifier=null; }
    public static bool IsCallback(string value) { Uri uri; return value!=null && value.Length<=8192 && Uri.TryCreate(value,UriKind.Absolute,out uri) && uri.Scheme=="aetheria-launcher" && uri.Host=="oauth-callback" && uri.UserInfo=="" && uri.Port==-1 && (uri.AbsolutePath=="" || uri.AbsolutePath=="/") && uri.Fragment==""; }
    public Dictionary<string,object> Accept(string value) {
        if(!pending || DateTime.UtcNow>expires || !IsCallback(value)) { Cancel(); throw new LauncherException("The sign-in request expired or was cancelled. Please sign in again."); }
        var fields=HttpUtility.ParseQueryString(new Uri(value).Query);
        string state=fields["state"], code=fields["code"];
        bool equal=state!=null && State!=null && state.Length==State.Length;
        int diff=0; if(equal) for(int i=0;i<state.Length;i++) diff|=state[i]^State[i];
        if(!equal || diff!=0 || String.IsNullOrWhiteSpace(code) || code.Length>4096 || fields.GetValues("state").Length!=1 || fields.GetValues("code").Length!=1 || fields["error"]!=null) { Cancel(); throw new LauncherException("Sign-in could not be verified. Please sign in again."); }
        var result=new Dictionary<string,object> { {"code",code}, {"codeVerifier",verifier}, {"redirectUri",RedirectUri}, {"clientId",clientId} }; Cancel(); return result;
    }
}
internal interface IButlerRpc { Task<Dictionary<string,object>> Call(string method,object args,int timeout); }
internal sealed class RpcClient : IButlerRpc,IDisposable {
    TcpClient client; StreamWriter writer; readonly object sync=new object(),writeSync=new object();
    readonly Dictionary<string,TaskCompletionSource<Dictionary<string,object>>> pending=new Dictionary<string,TaskCompletionSource<Dictionary<string,object>>>();
    long sequence; bool authenticated,disposed;
    public event Action<string,Dictionary<string,object>> Notification;
    public static IPEndPoint ParseEndpoint(string address) {
        Uri parsed; IPAddress ip;
        if(!Uri.TryCreate("tcp://"+address,UriKind.Absolute,out parsed) || !IPAddress.TryParse(parsed.Host.Trim('[',']'),out ip) || !IPAddress.IsLoopback(ip) || parsed.Port<1 || parsed.Port>65535 || parsed.UserInfo!="" || parsed.AbsolutePath!="/") throw new LauncherException("The download service returned an invalid local address.");
        return new IPEndPoint(ip,parsed.Port);
    }
    public async Task Connect(string address,string secret) {
        var endpoint=ParseEndpoint(address); client=new TcpClient(endpoint.AddressFamily);
        var connect=client.ConnectAsync(endpoint.Address,endpoint.Port); if(await Task.WhenAny(connect,Task.Delay(5000))!=connect) { Dispose(); throw new LauncherException("The local download service did not respond. Please retry."); } await connect;
        var stream=client.GetStream(); writer=new StreamWriter(stream,new UTF8Encoding(false)) {AutoFlush=true,NewLine="\n"};
        ThreadPool.QueueUserWorkItem(delegate { ReadLoop(new StreamReader(stream,Encoding.UTF8,false,4096,true)); });
        var result=await Call("Meta.Authenticate",new {secret=secret},5000); if(!Json.Flag(result,"ok")) { Dispose(); throw new LauncherException("The local download service could not authenticate."); } authenticated=true;
    }
    public async Task<Dictionary<string,object>> Call(string method,object args,int timeout) {
        if(disposed || writer==null || (!authenticated && method!="Meta.Authenticate")) throw new LauncherException("The download service is not connected. Restart the launcher and retry.");
        var completion=new TaskCompletionSource<Dictionary<string,object>>(); string id=Interlocked.Increment(ref sequence).ToString(System.Globalization.CultureInfo.InvariantCulture);
        lock(sync) pending.Add(id,completion);
        try {
            Send(new {jsonrpc="2.0",id=Int64.Parse(id),method=method,@params=args});
            if(await Task.WhenAny(completion.Task,Task.Delay(timeout))!=completion.Task) throw new LauncherException("The download service took too long. Please retry.");
            return await completion.Task;
        } finally { lock(sync) pending.Remove(id); }
    }
    void Send(object message) { lock(writeSync) { if(disposed) throw new IOException(); writer.WriteLine(Json.Stringify(message)); } }
    void ReadLoop(StreamReader reader) {
        try {
            string line; while((line=Json.ReadLine(reader,4*1024*1024))!=null) {
                var message=Json.Parse(line); if(message==null || Json.Text(message,"jsonrpc")!="2.0") throw new IOException();
                object id; bool hasId=message.TryGetValue("id",out id); string method=Json.Text(message,"method");
                if(method!="") {
                    if(hasId) Send(new {jsonrpc="2.0",id=id,error=new {code=-32601,message="This launcher does not support interactive actions."}});
                    else { var callback=Notification; if(callback!=null) callback(method,Json.Object(message,"params")); }
                } else if(hasId) {
                    TaskCompletionSource<Dictionary<string,object>> completion;
                    lock(sync) pending.TryGetValue(Convert.ToString(id,System.Globalization.CultureInfo.InvariantCulture),out completion);
                    if(completion!=null) {
                        if(message.ContainsKey("error")) completion.TrySetException(new LauncherException("itch.io could not complete the request. Check your beta access and sign in again."));
                        else completion.TrySetResult(Json.Object(message,"result") ?? new Dictionary<string,object>());
                    }
                }
            }
        } catch {} finally { disposed=true; FailPending(); }
    }
    void FailPending() { TaskCompletionSource<Dictionary<string,object>>[] completions;lock(sync) {completions=new TaskCompletionSource<Dictionary<string,object>>[pending.Count];pending.Values.CopyTo(completions,0);}foreach(var completion in completions) completion.TrySetException(new LauncherException("The download service disconnected. Restart the launcher and retry.")); }
    public void Dispose() { disposed=true; authenticated=false; if(client!=null) client.Close(); FailPending(); }
}
internal sealed class ButlerDaemon : IDisposable {
    Process process; public RpcClient Rpc {get;private set;}
    public async Task Start(string executable,string state) {
        Directory.CreateDirectory(state); SafePath.DemandNoReparse(state); SafePath.DemandNoReparse(executable);
        if(!File.Exists(executable)) throw new LauncherException("The bundled download service is missing. Please extract the complete launcher download.");
        var ready=new TaskCompletionSource<Dictionary<string,object>>();
        process=new Process { StartInfo=new ProcessStartInfo { FileName=executable, Arguments="daemon --json --transport tcp --keep-alive --dbpath \""+Path.Combine(state,"butler.db")+"\" --address https://api.itch.io --user-agent AetheriaLauncher/1 --destiny-pid "+Process.GetCurrentProcess().Id,UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=state} };
        process.Start();
        var started=process;
        ThreadPool.QueueUserWorkItem(delegate { try { string line; while((line=Json.ReadLine(started.StandardOutput,1024*1024))!=null) { try { var item=Json.Parse(line); if(Json.Text(item,"type")=="butlerd/listen-notification") ready.TrySetResult(item); } catch {} } ready.TrySetException(new LauncherException("The local download service closed unexpectedly.")); } catch { ready.TrySetException(new LauncherException("The local download service could not start.")); } });
        ThreadPool.QueueUserWorkItem(delegate { try { while(Json.ReadLine(started.StandardError,1024*1024)!=null) {} } catch {} });
        if(await Task.WhenAny(ready.Task,Task.Delay(15000))!=ready.Task) { Dispose(); throw new LauncherException("The local download service could not start. Please retry."); }
        try {
            var details=await ready.Task; string secret=Json.Text(details,"secret"); if(secret.Length<8 || secret.Length>4096) throw new IOException();
            Rpc=new RpcClient(); await Rpc.Connect(Json.Text(Json.Object(details,"tcp"),"address"),secret);
            var version=await Rpc.Call("Version.Get",new {},5000); if(Json.Text(version,"version")!="v15.32.0") throw new LauncherException("The bundled download service has the wrong version. Please download a fresh launcher.");
            // butler's rate is kilobits per second: 500,000 bytes/s * 8 / 1,000.
            await Rpc.Call("Network.SetBandwidthThrottle",new {enabled=true,rate=4000},5000);
        } catch { Dispose(); throw; }
    }
    public void Dispose() { if(Rpc!=null) Rpc.Dispose(); if(process!=null) { try { if(!process.HasExited) { process.Kill(); process.WaitForExit(2000); } } catch {} process.Dispose(); process=null; } }
}
}
