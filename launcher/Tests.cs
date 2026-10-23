using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Windows.Forms;

namespace AetheriaLauncher {
internal static class LauncherTests {
    static int count;
    static void Assert(bool value, string name) { if (!value) throw new Exception("FAIL: " + name); count++; Console.WriteLine("PASS: " + name); }
    static void Reject(Action action, string name) { bool rejected=false; try { action(); } catch { rejected=true; } Assert(rejected,name); }
    static Dictionary<string,object> Release() { return Json.Parse("{\"ok\":true,\"enabled\":true,\"release_id\":\"beta-1\",\"client_sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\",\"client_bytes\":3}"); }
    [STAThread] public static int Main(string[] args) {
        string root=Path.Combine(Path.GetTempPath(),"aetheria-launcher-tests-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try {
            Assert(Json.Array(Json.Parse("{\"items\":[{\"id\":1}]}"),"items").Length==1,"JSON RPC result arrays retain profiles, uploads and caves");
            string game=Path.Combine(root,"games","aetheria"); Directory.CreateDirectory(game);
            File.WriteAllText(Path.Combine(game,"Aetheria.exe"),"abc",new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(game,"release.json"),"{\"schema\":1,\"release_id\":\"beta-1\",\"executable\":\"Aetheria.exe\"}");
            Assert(ReleaseGate.Verify(Path.Combine(root,"games"),game,Release(),false)==Path.Combine(game,"Aetheria.exe"),"verified HTTPS release metadata accepts matching EXE and manifest");
            var bad=Release(); bad["client_sha256"]=new string('0',64); Reject(()=>ReleaseGate.Verify(Path.Combine(root,"games"),game,bad,false),"EXE hash mismatch blocks Play");
            bad=Release(); bad["release_id"]="beta-2"; Reject(()=>ReleaseGate.Verify(Path.Combine(root,"games"),game,bad,false),"release version mismatch blocks Play");
            bad=Release(); bad["enabled"]=false; Reject(()=>ReleaseGate.Verify(Path.Combine(root,"games"),game,bad,false),"disabled release blocks Play");
            Reject(()=>ReleaseGate.Verify(Path.Combine(root,"games"),game,null,false),"offline or absent release blocks Play");
            Reject(()=>ReleaseGate.Verify(Path.Combine(root,"games"),game,Release(),true),"interrupted update marker blocks Play");
            File.WriteAllText(Path.Combine(game,"release.json"),"{\"schema\":1,\"release_id\":\"beta-1\",\"executable\":\"../Aetheria.exe\"}");
            Reject(()=>ReleaseGate.Verify(Path.Combine(root,"games"),game,Release(),false),"manifest path traversal blocks Play");
            Reject(()=>SafePath.Within(Path.Combine(root,"games"),root),"install directory escape rejected");
            var flow=new OAuthFlow(); string url=flow.Begin("client");
            Assert(url.StartsWith("https://itch.io/user/oauth?") && url.Contains("code_challenge_method=S256"),"consumer OAuth uses itch PKCE authorize endpoint");
            Assert(System.Web.HttpUtility.ParseQueryString(new Uri(url).Query)["scope"]=="profile:me profile:owned game:view:uploads","third-party launcher requests supported read/download scopes only");
            Reject(()=>flow.Accept("aetheria-launcher://oauth-callback?code=test&state=wrong"),"OAuth state mismatch rejected");
            flow=new OAuthFlow(); flow.Begin("client");
            var result=flow.Accept("aetheria-launcher://oauth-callback?code=approved&state="+Uri.EscapeDataString(flow.State));
            Assert(Json.Text(result,"code")=="approved" && Json.Text(result,"codeVerifier").Length>=43,"OAuth callback provides original verifier for code exchange");
            Reject(()=>flow.Accept("aetheria-launcher://oauth-callback?code=replay&state="+flow.State),"OAuth callback cannot be replayed");
            flow=new OAuthFlow(); flow.Begin("client"); flow.Cancel(); Reject(()=>flow.Accept("aetheria-launcher://oauth-callback?code=test&state="+flow.State),"cancelled OAuth callback rejected");
            Reject(()=>new HttpsReleaseSource("http://127.0.0.1").Get().GetAwaiter().GetResult(),"release service rejects unencrypted HTTP");
            Reject(()=>new HttpsReleaseSource("https://user:password@example.invalid").Get().GetAwaiter().GetResult(),"release service rejects credential-bearing URLs");
            Reject(()=>RpcClient.ParseEndpoint("192.0.2.1:80"),"daemon must listen on loopback");
            RpcTest().GetAwaiter().GetResult();
            PipeTest();
            ServiceTest(Path.Combine(root,"service")).GetAwaiter().GetResult();
            TwoProfileTest(Path.Combine(root,"two-profiles")).GetAwaiter().GetResult();
            using(var form=new LauncherForm()) {
                form.ShowInTaskbar=false;form.Opacity=0;form.Show();Application.DoEvents();
                bool hasSign=false,hasUpdate=false,playDisabled=false;
                foreach(Control control in form.Controls) {var button=control as Button;if(button==null)continue;if(button.Text=="Sign in to itch.io")hasSign=true;if(button.Text=="Check / update")hasUpdate=true;if(button.Text=="Play")playDisabled=!button.Enabled;}
                Assert(hasSign && hasUpdate && playDisabled,"WinForms first screen opens with sign-in, update and fail-closed Play");form.Close();
            }
            if(args.Length==2 && args[0]=="--butler") {
                using(var daemon=new ButlerDaemon()) {
                    daemon.Start(args[1],Path.Combine(root,"real")).GetAwaiter().GetResult();
                    var version=daemon.Rpc.Call("Version.Get",new {},5000).GetAwaiter().GetResult();
                    Assert(Json.Text(version,"version")=="v15.32.0","real pinned butler authenticates and returns expected version");
                    var profiles=daemon.Rpc.Call("Profile.List",new {},5000).GetAwaiter().GetResult();
                    Assert(Json.Array(profiles,"profiles").Length==0,"real isolated butler database has no credentials");
                    string location=Path.Combine(root,"real","games");Directory.CreateDirectory(location);
                    awaitResult(daemon.Rpc.Call("Install.Locations.Add",new {id="launcher-test",path=location},5000));
                    var locations=awaitResult(daemon.Rpc.Call("Install.Locations.List",new {},5000));
                    Assert(Json.Array(locations,"installLocations").Length==1,"real daemon persists and lists fixed install location");
                    var caves=awaitResult(daemon.Rpc.Call("Fetch.Caves",new {filters=new {gameId=5211819},limit=100},5000));
                    Assert(Json.Array(caves,"items").Length==0,"real daemon accepts game-scoped cave query");
                    var ownership=awaitResult(daemon.Rpc.Call("Fetch.GameOwnership",new {profileId=42,gameId=5211819},5000));
                    Assert(!Json.Flag(ownership,"owned"),"real daemon supports strict profile-scoped ownership and denies unknown consumer");
                }
            }
            Console.WriteLine("Launcher checks passed: "+count); return 0;
        } catch(Exception ex) { Console.Error.WriteLine(ex.Message); return 1; }
        finally { try { Directory.Delete(root,true); } catch {} }
    }
    static Dictionary<string,object> awaitResult(Task<Dictionary<string,object>> task) {return task.GetAwaiter().GetResult();}
    static void PipeTest() {
        string name="aetheria-launcher-test-"+Guid.NewGuid().ToString("N");
        using(var delivered=new AutoResetEvent(false))using(var pipe=new CallbackPipe(name)) {
            string received="";pipe.Received+=uri=>{received=uri;delivered.Set();};pipe.Start();
            string expected="aetheria-launcher://oauth-callback?code=test&state=test";
            Assert(CallbackPipe.Send(name,expected) && delivered.WaitOne(2000) && received==expected,"same-user callback pipe delivers a bounded OAuth URI");
            CallbackPipe.Send(name,"file:///C:/Windows/System32/cmd.exe");Assert(!delivered.WaitOne(200),"callback pipe rejects arbitrary paths and commands");
        }
    }
    sealed class ReleaseFixture : IReleaseSource {
        public bool Offline; public int Calls;
        public Task<Dictionary<string,object>> Get() {Calls++;if(Offline)throw new LauncherException("offline fixture");return Task.FromResult(Release());}
    }
    sealed class ButlerFixture : IButlerRpc {
        public readonly string Folder; public bool FailLogin,Interrupt,DenyAccess,TwoProfiles,BInvited,StaleOwnership,StaleKeys; public bool UpdateContract;public long OAuthProfile=42,OwnershipKey=9001;public string OwnershipSource="download_key";public int GlobalUploads,OwnershipChecks,OwnershipRefreshes;
        public ButlerFixture(string folder) {Folder=folder;}
        Dictionary<string,object> Cave() {return new Dictionary<string,object> {{"id","our-cave"},{"game",new Dictionary<string,object>{{"id",123}}},{"upload",new Dictionary<string,object>{{"id",456}}},{"installInfo",new Dictionary<string,object>{{"installFolder",Folder}}}};}
        public Task<Dictionary<string,object>> Call(string method,object args,int timeout) {
            var input=Json.Parse(Json.Stringify(args));
            Dictionary<string,object> result=new Dictionary<string,object>();
            switch(method) {
                case "Profile.List":result["profiles"]=TwoProfiles ? new object[]{new Dictionary<string,object>{{"id",42},{"user",new Dictionary<string,object>{{"id",42},{"username","invited-A"}}}},new Dictionary<string,object>{{"id",84},{"user",new Dictionary<string,object>{{"id",84},{"username","uninvited-B"}}}}} : new object[]{new Dictionary<string,object>{{"id",42},{"lastConnected","2026-10-22T00:00:00Z"},{"user",new Dictionary<string,object>{{"id",42},{"username","tester"}}}}};break;
                case "Profile.UseSavedLogin":if(FailLogin)throw new LauncherException("failed login fixture");if(Json.Number(input,"profileId")!=42 && !(TwoProfiles && Json.Number(input,"profileId")==84))throw new Exception("wrong profile");result["profile"]=new Dictionary<string,object>{{"id",Json.Number(input,"profileId")}};break;
                case "Profile.LoginWithOAuthCode":result["profile"]=new Dictionary<string,object>{{"id",OAuthProfile}};result["cookie"]=new Dictionary<string,object>();break;
                case "Fetch.ProfileOwnedKeys":
                    if(!Json.Flag(input,"fresh") || (Json.Number(input,"profileId")!=42 && !(TwoProfiles && Json.Number(input,"profileId")==84)))throw new Exception("ownership refresh must be selected-profile scoped and fresh");
                    OwnershipRefreshes++;result["items"]=new object[0];result["stale"]=StaleKeys;result["nextCursor"]=null;break;
                case "Fetch.GameOwnership":
                    if(Json.Number(input,"gameId")!=123 || (Json.Number(input,"profileId")!=42 && !(TwoProfiles && Json.Number(input,"profileId")==84)))throw new Exception("ownership query is not selected-profile scoped");
                    OwnershipChecks++;bool owns=!DenyAccess && (Json.Number(input,"profileId")==42 || BInvited);result["owned"]=owns;result["source"]=owns ? OwnershipSource : "";if(owns)result["downloadKeyId"]=OwnershipKey;result["stale"]=StaleOwnership;break;
                case "Fetch.GameUploads":GlobalUploads++;if(Json.Number(input,"gameId")!=123 || !Json.Flag(input,"fresh") || !Json.Flag(input,"compatible"))throw new Exception("unscoped upload fetch");result["uploads"]=DenyAccess ? new object[0] : new object[]{new Dictionary<string,object>{{"id",456},{"storage","build"},{"build",new Dictionary<string,object>{{"id",789}}}}};result["stale"]=false;break;
                case "Fetch.Caves":if(Json.Number(Json.Object(input,"filters"),"gameId")!=123)throw new Exception("unscoped cave fetch");result["items"]=new object[]{Cave()};result["nextCursor"]=null;break;
                case "CheckUpdate":var ids=Json.Array(input,"caveIds");if(ids.Length!=1 || Convert.ToString(ids[0])!="our-cave")throw new Exception("unscoped update");result["updates"]=new object[0];result["warnings"]=new object[0];break;
                case "Install.Locations.List":result["installLocations"]=new object[]{new Dictionary<string,object>{{"id","location"},{"path",Path.GetDirectoryName(Folder)},{"sizeInfo",new Dictionary<string,object>{{"totalSize",100}}}}};break;
                case "Fetch.Game":result["game"]=new Dictionary<string,object>{{"id",123},{"title","Aetheria"},{"url","https://example.itch.io/aetheria"}};result["stale"]=false;break;
                case "Install.Queue":
                    UpdateContract=Json.Flag(input,"ignoreInstallers") && Json.Number(input,"profileId")==42 && Json.Text(input,"caveId")=="our-cave" && Json.Number(Json.Object(input,"upload"),"id")==456 && Json.Number(Json.Object(input,"game"),"id")==123 && Json.Number(Json.Object(input,"build"),"id")==789;
                    if(!UpdateContract)throw new Exception("unsafe install contract");result["id"]="task";result["game"]=Json.Object(input,"game");result["upload"]=Json.Object(input,"upload");result["installFolder"]=Folder;result["stagingFolder"]=Path.Combine(Path.GetDirectoryName(Folder),"downloads","staging");break;
                case "Install.Perform":
                    if(Interrupt)throw new LauncherException("interrupted fixture");
                    File.WriteAllText(Path.Combine(Folder,"release.json"),"{\"schema\":1,\"release_id\":\"beta-1\",\"executable\":\"Aetheria.exe\"}");result["caveId"]="our-cave";result["events"]=new object[0];break;
                case "Install.Cancel":break;
                default:throw new Exception("Unexpected fixture call: "+method);
            }
            return Task.FromResult(result);
        }
    }
    static async Task ServiceTest(string state) {
        string folder=Path.Combine(state,"games","aetheria");Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder,"Aetheria.exe"),"abc",new UTF8Encoding(false));
        string manifest=Path.Combine(folder,"release.json");File.WriteAllText(manifest,"{\"schema\":1,\"release_id\":\"beta-1\",\"executable\":\"Aetheria.exe\"}");
        var settings=new LauncherConfig {GameId=123,UploadId=456,OAuthClientId="client",AccountUrl="https://example.invalid"};
        var rpc=new ButlerFixture(folder);var source=new ReleaseFixture();var service=new LauncherService(settings,state,rpc,source);
        await service.Initialize();Assert(service.Ready,"validated saved login and matching installation enable Play");
        source.Offline=true;bool failed=false;try {await service.Play();}catch(LauncherException){failed=true;}Assert(failed && !service.Ready,"offline release recheck blocks Play even after successful startup");
        source.Offline=false;rpc.FailLogin=true;service=new LauncherService(settings,state,rpc,source);
        failed=false;try {await service.Initialize();}catch(LauncherException){failed=true;}Assert(failed && !service.Ready && !service.SignedIn,"failed saved authentication never enables Play");
        rpc.FailLogin=false;rpc.DenyAccess=true;service=new LauncherService(settings,state,rpc,source);
        failed=false;try {await service.Initialize();}catch(LauncherException){failed=true;}Assert(failed && !service.Ready && !service.SignedIn,"valid itch.io account without beta access cannot enable Play");rpc.DenyAccess=false;
        rpc.FailLogin=false;service=new LauncherService(settings,state,rpc,source);await service.Initialize();
        File.WriteAllText(manifest,"{\"schema\":1,\"release_id\":\"beta-old\",\"executable\":\"Aetheria.exe\"}");rpc.Interrupt=true;
        failed=false;try {await service.Update();}catch(LauncherException){failed=true;}
        Assert(failed && !service.Ready && File.Exists(Path.Combine(state,"update-in-progress")),"interrupted install persists fail-closed marker");
        Assert(rpc.UpdateContract,"update pins game/upload/build and disables external installers");
        failed=false;try {await service.Update();}catch(LauncherException){failed=true;}Assert(failed && !service.Ready,"uncertain butler operation cannot start another update before restart");
        rpc.Interrupt=false;service=new LauncherService(settings,state,rpc,source);
        try {await service.Initialize();}catch(LauncherException){}
        Assert(!service.Ready,"restarted launcher cannot play interrupted installation");
        int before=source.Calls;await service.Update();Assert(service.Ready && !File.Exists(Path.Combine(state,"update-in-progress")),"successful repair clears marker only after hash/version verification");
        Assert(source.Calls>=before+2,"update fetches trusted release both before and after installation");
    }
    static async Task TwoProfileTest(string state) {
        string folder=Path.Combine(state,"games","aetheria");Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder,"Aetheria.exe"),"abc",new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(folder,"release.json"),"{\"schema\":1,\"release_id\":\"beta-1\",\"executable\":\"Aetheria.exe\"}");
        File.WriteAllText(Path.Combine(state,"profile-id.txt"),"84");
        var config=new LauncherConfig {GameId=123,UploadId=456,OAuthClientId="client",AccountUrl="https://example.invalid"};
        var rpc=new ButlerFixture(folder){TwoProfiles=true,OAuthProfile=84};var release=new ReleaseFixture();
        // This fixture always returns the private upload through saved invited A,
        // including while B is selected. The real service must reject B independently.
        var service=new LauncherService(config,state,rpc,release);bool rejected=false;
        try {await service.Initialize();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"selected uninvited B fails startup despite invited A saved in same database");
        service=new LauncherService(config,state,rpc,release);rejected=false;
        try {await service.Login(new Dictionary<string,object>{{"code","fixture-code"}});}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"OAuth login as uninvited B cannot inherit saved A entitlement");
        rpc.BInvited=true;service=new LauncherService(config,state,rpc,release);await service.Initialize();rpc.BInvited=false;rejected=false;
        try {await service.Update();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"selected B loses update permission when its own invitation is removed");
        rpc.BInvited=true;service=new LauncherService(config,state,rpc,release);await service.Initialize();rpc.BInvited=false;rejected=false;
        try {await service.Play();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready && !service.GameRunning,"selected B cannot Play using invited A after B entitlement revocation");
        File.WriteAllText(Path.Combine(state,"profile-id.txt"),"42");service=new LauncherService(config,state,rpc,release);await service.Initialize();await service.Update();
        Assert(service.Ready,"invited A remains usable with uninvited B saved alongside it");
        Assert(rpc.OwnershipChecks>0 && rpc.OwnershipChecks==rpc.OwnershipRefreshes,"every selected-profile ownership query follows fresh profile-key synchronization");
        rpc.StaleOwnership=true;rejected=false;try {await service.Update();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"stale ownership marker cannot authorize an update");
        rpc.StaleOwnership=false;rpc.StaleKeys=true;service=new LauncherService(config,state,rpc,release);rejected=false;try {await service.Initialize();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"stale selected-profile key refresh cannot authorize startup");
        rpc.StaleKeys=false;rpc.OwnershipSource="bundle";service=new LauncherService(config,state,rpc,release);rejected=false;try {await service.Initialize();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"restricted beta requires a claimed consumer download key rather than bundle marker");
        rpc.OwnershipSource="download_key";rpc.OwnershipKey=0;service=new LauncherService(config,state,rpc,release);rejected=false;try {await service.Initialize();}catch(LauncherException){rejected=true;}
        Assert(rejected && !service.Ready,"missing consumer download key identifier cannot authorize startup");
    }
    static async Task RpcTest() {
        var listener=new TcpListener(IPAddress.Loopback,0); listener.Start();
        int port=((IPEndPoint)listener.LocalEndpoint).Port; bool promptRejected=false; bool authenticated=false;
        var server=Task.Run(async delegate {
            using(var client=await listener.AcceptTcpClientAsync()) using(var stream=client.GetStream()) using(var reader=new StreamReader(stream)) using(var writer=new StreamWriter(stream,new UTF8Encoding(false)) {AutoFlush=true}) {
                var auth=Json.Parse(await reader.ReadLineAsync()); authenticated=Json.Text(auth,"method")=="Meta.Authenticate" && Json.Text(Json.Object(auth,"params"),"secret")=="private-test-secret";
                writer.WriteLine(Json.Stringify(new {jsonrpc="2.0",id=auth["id"],result=new {ok=true}}));
                var a=Json.Parse(await reader.ReadLineAsync()); var b=Json.Parse(await reader.ReadLineAsync());
                writer.WriteLine("{\"jsonrpc\":\"2.0\",\"method\":\"Progress\",\"params\":{\"progress\":0.5,\"eta\":1,\"bps\":500000}}");
                writer.WriteLine("{\"jsonrpc\":\"2.0\",\"id\":\"prompt\",\"method\":\"ExecuteUnknownAction\",\"params\":{}}");
                var rejection=Json.Parse(await reader.ReadLineAsync()); promptRejected=Json.Text(rejection,"id")=="prompt" && rejection.ContainsKey("error");
                writer.WriteLine(Json.Stringify(new {jsonrpc="2.0",id=b["id"],result=new {value=Json.Text(b,"method")}}));
                writer.WriteLine(Json.Stringify(new {jsonrpc="2.0",id=a["id"],result=new {value=Json.Text(a,"method")}}));
            }
        });
        using(var rpc=new RpcClient()) {
            int progress=0; rpc.Notification+=(method,data)=> { if(method=="Progress") Interlocked.Increment(ref progress); };
            await rpc.Connect("127.0.0.1:"+port,"private-test-secret");
            var a=rpc.Call("First",new {},5000); var b=rpc.Call("Second",new {},5000);
            Assert(Json.Text(await a,"value")=="First" && Json.Text(await b,"value")=="Second","RPC responses correlate when returned out of order");
            await server; Assert(authenticated,"RPC authenticates before other requests"); Assert(progress==1,"RPC progress notification dispatched while requests pending"); Assert(promptRejected,"unknown server prompt receives explicit JSON-RPC error");
        }
        listener.Stop();
    }
}
}
