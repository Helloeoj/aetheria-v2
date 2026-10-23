using System;
using System.IO;
using System.Diagnostics;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace AetheriaLauncher {
// Every public operation is serialized. A durable marker survives process loss during an update.
internal sealed class LauncherService {
    readonly LauncherConfig config; readonly IButlerRpc rpc; readonly IReleaseSource releases;
    readonly string state, games, marker; readonly SemaphoreSlim operation=new SemaphoreSlim(1,1);
    Dictionary<string,object> cave,release,ownedGame; long profileId; Process game; bool uncertainUpdate;
    public bool Ready {get;private set;}
    public string Version {get { return release==null ? "No verified release" : "Release "+Json.Text(release,"release_id"); }}
    public bool SignedIn {get {return profileId>0;}}
    public bool GameRunning {get {try {return game!=null && !game.HasExited;} catch {return false;}}}
    public LauncherService(LauncherConfig settings,string directory,IButlerRpc butler,IReleaseSource source) {
        config=settings; rpc=butler; releases=source; state=directory; games=Path.Combine(state,"games"); marker=Path.Combine(state,"update-in-progress");
        Directory.CreateDirectory(games); SafePath.DemandNoReparse(state);
    }
    public async Task Initialize() {
        await operation.WaitAsync(); Ready=false;
        try {
            // Release is always fetched on startup, including when there is no saved itch.io profile.
            release=await releases.Get(); ReleaseGate.Validate(release);
            var profiles=await rpc.Call("Profile.List",new {},5000);
            long preferred=0;try {Int64.TryParse(Json.ReadSmall(Path.Combine(state,"profile-id.txt")),out preferred);}catch {}
            foreach(var item in Json.Array(profiles,"profiles")) {long id=Json.Number(item as Dictionary<string,object>,"id");if(id<=0)continue;if(profileId==0)profileId=id;if(id==preferred){profileId=id;break;}}
            await Authenticate(); await GetUpload(); await FindCave(); await Verify(false);
        } catch { Ready=false; throw; } finally {operation.Release();}
    }
    public async Task Login(Dictionary<string,object> exchange) {
        await operation.WaitAsync(); Ready=false; profileId=0;
        try {
            var response=await rpc.Call("Profile.LoginWithOAuthCode",exchange,15000);
            profileId=Json.Number(Json.Object(response,"profile"),"id"); if(profileId<=0) throw new LauncherException("Sign-in did not complete. Please sign in again.");
            await GetUpload();
            string preference=Path.Combine(state,"profile-id.txt");SafePath.DemandNoReparse(preference);File.WriteAllText(preference,profileId.ToString(System.Globalization.CultureInfo.InvariantCulture));
            await FindCave(); release=await releases.Get();
            if(cave!=null) await Verify(false);
        } catch { Ready=false; throw; } finally {operation.Release();}
    }
    async Task Authenticate() {
        if(profileId<=0) throw new LauncherException("Sign in to itch.io with your invited beta account to continue.");
        try { var result=await rpc.Call("Profile.UseSavedLogin",new {profileId=profileId},5000); if(Json.Number(Json.Object(result,"profile"),"id")!=profileId) throw new Exception(); }
        catch {profileId=0; Ready=false; throw new LauncherException("Your itch.io sign-in could not be verified. Check your connection and sign in again.");}
    }
    async Task<Dictionary<string,object>> GetUpload() {
        await RequireSelectedProfileOwnership();
        var result=await rpc.Call("Fetch.GameUploads",new {gameId=config.GameId,compatible=true,fresh=true},15000);
        foreach(var item in Json.Array(result,"uploads")) {
            var upload=item as Dictionary<string,object>;
            if(Json.Number(upload,"id")==config.UploadId) {
                if(Json.Text(upload,"storage")!="hosted" && Json.Text(upload,"storage")!="build") throw new LauncherException("This beta upload is not supported by the launcher. Please retry later.");
                return upload;
            }
        }
        profileId=0; throw new LauncherException("This itch.io account cannot access the beta download. Sign in with your invited account.");
    }
    async Task RequireSelectedProfileOwnership() {
        ownedGame=null;
        if(profileId<=0) throw new LauncherException("Sign in to itch.io with your invited beta account to continue.");
        // v15.32.0: fresh ProfileOwnedKeys refreshes/replaces all keys for this profile
        // before applying the result-page limit. GameOwnership itself is local-only
        // and strictly matches owner_id + game_id, unlike GameUploads/Install.Queue,
        // whose credential resolver can fall back to another remembered profile.
        var keys=await rpc.Call("Fetch.ProfileOwnedKeys",new {profileId=profileId,fresh=true,limit=100},15000);
        var ownership=await rpc.Call("Fetch.GameOwnership",new {profileId=profileId,gameId=config.GameId},5000);
        if(Json.Flag(keys,"stale") || !Json.Flag(ownership,"owned") || Json.Flag(ownership,"stale") || Json.Text(ownership,"source")!="download_key" || Json.Number(ownership,"downloadKeyId")<=0) {
            profileId=0; Ready=false;
            throw new LauncherException("This account does not own a beta invitation. Claim your invitation on itch.io, then sign in with that account.");
        }
        // The approved profile:owned response already includes game metadata.
        // Fetch.Game(fresh:true) instead needs the broader game:view scope.
        // Bind this metadata to the exact key independently verified above.
        for(int page=0;page<100;page++) {
            if(Json.Flag(keys,"stale")) break;
            foreach(var item in Json.Array(keys,"items")) {
                var key=item as Dictionary<string,object>;var metadata=Json.Object(key,"game");
                if(Json.Number(key,"id")==Json.Number(ownership,"downloadKeyId") && Json.Number(key,"ownerId")==profileId && Json.Number(key,"gameId")==config.GameId && Json.Number(metadata,"id")==config.GameId) {ownedGame=metadata;return;}
            }
            object cursor;if(!keys.TryGetValue("nextCursor",out cursor) || cursor==null)break;
            keys=await rpc.Call("Fetch.ProfileOwnedKeys",new {profileId=profileId,fresh=false,limit=100,cursor=cursor},15000);
        }
        throw new LauncherException("The beta invitation metadata could not be verified. Please retry later.");
    }
    async Task FindCave() {
        cave=null;
        var response=await rpc.Call("Fetch.Caves",new {filters=new {gameId=config.GameId},limit=100},5000);
        foreach(var item in Json.Array(response,"items")) {
            var candidate=item as Dictionary<string,object>;
            if(Json.Number(Json.Object(candidate,"game"),"id")==config.GameId && Json.Number(Json.Object(candidate,"upload"),"id")==config.UploadId) {
                string folder=Json.Text(Json.Object(candidate,"installInfo"),"installFolder");
                SafePath.Within(games,folder); if(String.IsNullOrEmpty(Json.Text(candidate,"id"))) throw new LauncherException("The game installation record is invalid. Please retry the update.");
                cave=candidate; return;
            }
        }
    }
    async Task<string> Verify(bool afterInstall) {
        if(profileId<=0 || cave==null) throw new LauncherException("The game is ready to install. Choose Check / update.");
        string folder=Json.Text(Json.Object(cave,"installInfo"),"installFolder");
        string exe=await Task.Run(()=>ReleaseGate.Verify(games,folder,release,!afterInstall && File.Exists(marker)));
        Ready=true; return exe;
    }
    public async Task Update() {
        await operation.WaitAsync(); Ready=false;
        try {
            if(uncertainUpdate) throw new LauncherException("The update was interrupted. Restart the launcher before repairing the game.");
            if(GameRunning) throw new LauncherException("Close Aetheria before updating it.");
            release=await releases.Get(); ReleaseGate.Validate(release); await Authenticate();
            var upload=await GetUpload(); await FindCave();
            if(cave!=null) {
                await rpc.Call("CheckUpdate",new {caveIds=new []{Json.Text(cave,"id")}},15000);
                // Keep the current installation when it is already the HTTPS-published release.
                try { await Verify(false); return; } catch {Ready=false;}
            }
            string locationId="";
            var locations=await rpc.Call("Install.Locations.List",new {},5000);
            foreach(var item in Json.Array(locations,"installLocations")) {
                var location=item as Dictionary<string,object>;
                if(String.Equals(Path.GetFullPath(Json.Text(location,"path")).TrimEnd('\\'),Path.GetFullPath(games).TrimEnd('\\'),StringComparison.OrdinalIgnoreCase)) locationId=Json.Text(location,"id");
            }
            if(locationId=="") {
                await rpc.Call("Install.Locations.Add",new {id="aetheria-beta",path=games},5000);
                locations=await rpc.Call("Install.Locations.List",new {},5000);
                foreach(var item in Json.Array(locations,"installLocations")) {var location=item as Dictionary<string,object>; if(String.Equals(Json.Text(location,"path").TrimEnd('\\'),games.TrimEnd('\\'),StringComparison.OrdinalIgnoreCase)) locationId=Json.Text(location,"id");}
                if(locationId=="") throw new LauncherException("The game install location could not be prepared. Please retry.");
            }
            var metadata=ownedGame;
            if(Json.Number(metadata,"id")!=config.GameId) throw new LauncherException("The beta download could not be identified. Please retry later.");
            bool repairing=File.Exists(marker);
            SafePath.DemandNoReparse(marker); using(var file=new FileStream(marker,FileMode.Create,FileAccess.Write,FileShare.None)) {file.WriteByte(1);file.Flush(true);}
            var request=new Dictionary<string,object> {{"game",metadata},{"upload",upload},{"installLocationId",locationId},{"ignoreInstallers",true},{"profileId",profileId},{"reason",cave==null ? "install" : (repairing ? "reinstall" : "update")}};
            if(cave!=null) request["caveId"]=Json.Text(cave,"id");
            // Explicitly pass the fresh channel build, avoiding the cave's previous build default.
            var build=Json.Object(upload,"build"); if(build!=null) request["build"]=build;
            var queued=await rpc.Call("Install.Queue",request,60000);
            if(Json.Number(Json.Object(queued,"game"),"id")!=config.GameId || Json.Number(Json.Object(queued,"upload"),"id")!=config.UploadId) throw new LauncherException("The beta download did not match this launcher. Please retry later.");
            SafePath.Within(games,Json.Text(queued,"installFolder")); SafePath.Within(games,Json.Text(queued,"stagingFolder"));
            string id=Json.Text(queued,"id"); if(id=="") throw new LauncherException("The update could not be prepared. Please retry.");
            bool interrupted=false;
            try {
                var installing=rpc.Call("Install.Perform",new {id=id,stagingFolder=Json.Text(queued,"stagingFolder")},60*60*1000);
                // Continue checking the selected invitation during long installs.
                // This also keeps the pinned daemon's API connection active: an
                // idled connection can double-close its shared throttle client
                // and starve an unrelated storage transfer of bandwidth tokens.
                while(await Task.WhenAny(installing,Task.Delay(20000))!=installing) await GetUpload();
                await installing;
            }
            catch {uncertainUpdate=true;interrupted=true;}
            if(interrupted) {
                try {await rpc.Call("Install.Cancel",new {id=id},5000);} catch {}
                throw new LauncherException("The update was interrupted. Restart the launcher, then choose Check / update to repair it.");
            }
            await FindCave(); release=await releases.Get(); await Verify(true);
            File.Delete(marker); Ready=true;
        } catch {Ready=false;throw;} finally {operation.Release();}
    }
    public async Task Play() {
        await operation.WaitAsync(); Ready=false;
        try {
            if(uncertainUpdate) throw new LauncherException("The update was interrupted. Restart the launcher before repairing the game.");
            if(GameRunning) throw new LauncherException("Aetheria is already running.");
            await Authenticate(); await GetUpload(); await FindCave();
            release=await releases.Get(); string exe=await Verify(false);
            SafePath.DemandNoReparse(exe);
            game=Process.Start(new ProcessStartInfo { FileName=exe,WorkingDirectory=Path.GetDirectoryName(exe),UseShellExecute=false });
            Ready=false;
        } catch {Ready=false;throw;} finally {operation.Release();}
    }
    public void Invalidate() {Ready=false;}
}
}
