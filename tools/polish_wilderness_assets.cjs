'use strict';

// Rebuild editable wilderness surfaces from unwarped original-map texture
// samples. The approved layout, object feet and original authored map survive.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const {polishObjects,polishBorderTrees} = require('./wilderness/polish_objects.cjs');
const PROJECT = path.resolve(__dirname, '../godot_client');
const outputArgument = process.argv.indexOf('--output-dir');
const POLISH = outputArgument >= 0 ? path.resolve(process.argv[outputArgument+1]) : path.resolve(__dirname,'../../exports/WildernessPolish_v1');
const LAYOUT = path.resolve(__dirname,'../art_sources/wilderness-v1/polish-layout');
const OUT = path.join(PROJECT, 'Assets/MapTiles/Wilderness');
const W = 3072, H = 3072, T = 32;
const rgba = async file => sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});
const write = async (data,w,h,file) => { fs.mkdirSync(path.dirname(file),{recursive:true}); await sharp(data,{raw:{width:w,height:h,channels:4}}).png().toFile(file); };
function hash(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function random(seed) { let n=seed|0; return () => { n^=n<<13; n^=n>>>17; n^=n<<5; return (n>>>0)/4294967296; }; }
function noise(x,y) { let n=Math.imul(x+497,73856093)^Math.imul(y+319,19349663); n^=n>>>16; return (n>>>0)/4294967296; }
function copy(dst,dp,src,sp) { src.copy(dst,dp*4,sp*4,sp*4+4); }

function samples(image,kind,size,blocked) {
 const {data,info:{width:w,height:h}}=image, candidates=[];
 const stride=w+1,transparent=new Int32Array(stride*(h+1));
 for(let y=0;y<h;y++){let sum=0;for(let x=0;x<w;x++){sum+=data[(y*w+x)*4+3]!==255?1:0;transparent[(y+1)*stride+x+1]=transparent[y*stride+x+1]+sum;}}
 for(let y=0;y<Math.min(h,1024)-size;y+=8) for(let x=0;x<w-size;x+=8) {
  if(kind==='Water'&&x<1240)continue;
  // These measured original-road stretches contain bare dirt, outside the
  // intentional paving at the gate and junctions.
  if(kind==='Paths'&&(x<1000||x>1210||(y>170&&y<660)))continue;
  if(transparent[(y+size)*stride+x+size]-transparent[y*stride+x+size]-transparent[(y+size)*stride+x]+transparent[y*stride+x])continue;
  let bad=0,sum=[0,0,0],count=0;
  for(let yy=0;yy<size;yy+=2)for(let xx=0;xx<size;xx+=2) {
   const q=((y+yy)*w+x+xx)*4,r=data[q],g=data[q+1],b=data[q+2]; count++;
   const good=data[q+3]===255&&(kind==='Grass' ? g>40&&g>r*.98&&b<g*.65 : kind==='Paths' ? r>85&&r-g>20&&g-b>18 : b>65&&b>r*1.15&&g>r*1.12);
   if(!good||(blocked&&blocked[(y+yy)*w+x+xx]))bad++; sum[0]+=r;sum[1]+=g;sum[2]+=b;
  }
  if(bad>count*(kind==='Grass'?.07:kind==='Paths'?.16:.005))continue;
  candidates.push({x,y,mean:sum.map(v=>v/count),bad});
 }
 if(candidates.length<4)throw new Error('Insufficient clean '+kind+' texture samples: '+candidates.length);
 // The same palette supplies every section. A narrower mean range prevents
 // low-frequency rectangular color shifts between individually lit samples.
 const means=candidates.map(c=>c.mean[1]).sort((a,b)=>a-b),median=means[means.length>>1];
 const filtered=candidates.filter(c=>Math.abs(c.mean[1]-median)<(kind==='Water'?14:8));
 return {candidates:filtered.length>=4?filtered:candidates,data,width:w,size};
}

// Texture quilting: source pixels remain at native scale. Minimum-error cuts
// hide patch joins rather than stretching pixels or blending them into blur.
function quilt(pool,w,h,seed) {
 const out=Buffer.alloc(w*h*4),rng=random(seed),P=pool.size,O=16,step=P-O;
 const {data:src,width:sw,candidates}=pool;
 for(let oy=0;oy<h;oy+=step)for(let ox=0;ox<w;ox+=step) {
  const pw=Math.min(P,w-ox),ph=Math.min(P,h-oy),left=ox>0,top=oy>0;
  let best=null,bestCost=Infinity;
  for(let attempt=0;attempt<48;attempt++) {
   const c=candidates[Math.floor(rng()*candidates.length)];let cost=0;
   if(left)for(let yy=0;yy<ph;yy+=3)for(let xx=0;xx<Math.min(O,pw);xx+=3){const a=((oy+yy)*w+ox+xx)*4,b=((c.y+yy)*sw+c.x+xx)*4;for(let k=0;k<3;k++){const d=out[a+k]-src[b+k];cost+=d*d;}}
   if(top)for(let yy=0;yy<Math.min(O,ph);yy+=3)for(let xx=left?O:0;xx<pw;xx+=3){const a=((oy+yy)*w+ox+xx)*4,b=((c.y+yy)*sw+c.x+xx)*4;for(let k=0;k<3;k++){const d=out[a+k]-src[b+k];cost+=d*d;}}
   if(cost<bestCost){bestCost=cost;best=c;} if(!left&&!top)break;
  }
  const error=(xx,yy)=>{const a=((oy+yy)*w+ox+xx)*4,b=((best.y+yy)*sw+best.x+xx)*4;let v=0;for(let k=0;k<3;k++){const d=out[a+k]-src[b+k];v+=d*d;}return v;};
  const vcut=new Int16Array(ph),hcut=new Int16Array(pw);
  if(left){const ow=Math.min(O,pw),dp=new Float64Array(ow*ph),parent=new Int16Array(ow*ph);for(let yy=0;yy<ph;yy++)for(let xx=0;xx<ow;xx++){let p=xx;if(yy){for(let k=Math.max(0,xx-1);k<=Math.min(ow-1,xx+1);k++)if(dp[(yy-1)*ow+k]<dp[(yy-1)*ow+p])p=k;}dp[yy*ow+xx]=error(xx,yy)+(yy?dp[(yy-1)*ow+p]:0);parent[yy*ow+xx]=p;}let p=0;for(let xx=1;xx<ow;xx++)if(dp[(ph-1)*ow+xx]<dp[(ph-1)*ow+p])p=xx;for(let yy=ph-1;yy>=0;yy--){vcut[yy]=p;p=parent[yy*ow+p];}}
  if(top){const oh=Math.min(O,ph),dp=new Float64Array(oh*pw),parent=new Int16Array(oh*pw);for(let xx=0;xx<pw;xx++)for(let yy=0;yy<oh;yy++){let p=yy;if(xx){for(let k=Math.max(0,yy-1);k<=Math.min(oh-1,yy+1);k++)if(dp[k*pw+xx-1]<dp[p*pw+xx-1])p=k;}dp[yy*pw+xx]=error(xx,yy)+(xx?dp[p*pw+xx-1]:0);parent[yy*pw+xx]=p;}let p=0;for(let yy=1;yy<oh;yy++)if(dp[yy*pw+pw-1]<dp[p*pw+pw-1])p=yy;for(let xx=pw-1;xx>=0;xx--){hcut[xx]=p;p=parent[p*pw+xx];}}
  for(let yy=0;yy<ph;yy++)for(let xx=0;xx<pw;xx++)if((!left||xx>=vcut[yy])&&(!top||yy>=hcut[xx]))copy(out,(oy+yy)*w+ox+xx,src,(best.y+yy)*sw+best.x+xx);
 }
 return out;
}

function distance(mask,w,h,inside) {
 const d=new Float32Array(w*h),big=w+h; for(let p=0;p<d.length;p++)d[p]=(mask[p]>0)===inside?big:0;
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const p=y*w+x;let v=d[p];if(x)v=Math.min(v,d[p-1]+1);if(y)v=Math.min(v,d[p-w]+1);if(x&&y)v=Math.min(v,d[p-w-1]+1.414);if(x<w-1&&y)v=Math.min(v,d[p-w+1]+1.414);d[p]=v;}
 for(let y=h-1;y>=0;y--)for(let x=w-1;x>=0;x--){const p=y*w+x;let v=d[p];if(x<w-1)v=Math.min(v,d[p+1]+1);if(y<h-1)v=Math.min(v,d[p+w]+1);if(x<w-1&&y<h-1)v=Math.min(v,d[p+w+1]+1.414);if(x&&y<h-1)v=Math.min(v,d[p+w-1]+1.414);d[p]=v;}
 return d;
}

function polygons(mask,tx,ty) {
 const active=new Map(),result=[];
 for(let gy=0;gy<=8;gy++){
  const runs=[];let start=-1;
  for(let gx=0;gx<=8;gx++){
   let solid=false;if(gy<8&&gx<8){let n=0;for(let yy=0;yy<4;yy++)for(let xx=0;xx<4;xx++)n+=mask[(ty*T+gy*4+yy)*W+tx*T+gx*4+xx]===2;solid=n>=8;}
   if(solid&&start<0)start=gx;if(!solid&&start>=0){runs.push([start,gx]);start=-1;}
  }
  const keys=new Set(runs.map(r=>r.join(',')));
  for(const[key,r]of active)if(!keys.has(key)){result.push([[r.x0*4-16,r.y0*4-16],[r.x1*4-16,r.y0*4-16],[r.x1*4-16,gy*4-16],[r.x0*4-16,gy*4-16]]);active.delete(key);}
  for(const[x0,x1]of runs){const key=[x0,x1].join(',');if(!active.has(key))active.set(key,{x0,x1,y0:gy});}
 }
 return result;
}

async function main(){
 fs.mkdirSync(POLISH,{recursive:true});
 const protectedFiles=['scenes/EastOutskirtsBlockout.tscn','scenes/PlayableMapContent.tscn','Assets/MapTiles/map_manifest.json','scripts/main.gd','scenes/EastOutskirtsLayered.tscn'];
 const before=Object.fromEntries(protectedFiles.map(p=>[p,hash(path.join(PROJECT,p))]));
 let manifest=JSON.parse(fs.readFileSync(path.join(LAYOUT,'layout.json')));
 const original=await Promise.all(['Grass','PathsAndQuays','Water'].map(n=>rgba(path.join(PROJECT,'Assets/MapTiles',n+'.png'))));
 const oldManifest=JSON.parse(fs.readFileSync(path.join(PROJECT,'Assets/MapTiles/map_manifest.json')));
 const blocked=new Uint8Array(original[0].info.width*original[0].info.height);
 for(const o of oldManifest.objects){const [x,y,w,h]=o.bbox;for(let yy=Math.max(0,y-4);yy<Math.min(original[0].info.height,y+h+4);yy++)for(let xx=Math.max(0,x-4);xx<Math.min(original[0].info.width,x+w+4);xx++)blocked[yy*original[0].info.width+xx]=1;}
 const pools=original.map((im,i)=>samples(im,['Grass','Paths','Water'][i],i===1?48:64,i===0?blocked:null));
 console.log('[Polish] Clean native texture samples:',pools.map(p=>p.candidates.length));
 const fields=[];
 for(let i=0;i<3;i++){console.log('[Polish] Quilting '+['grass','dirt','water'][i]+' without scaling.');fields.push(quilt(pools[i],W,H,817+i*101));}
 let road=await sharp(path.join(LAYOUT,'PathsMask.png')).greyscale().raw().toBuffer();
 const water=await sharp(path.join(LAYOUT,'WaterMask.png')).greyscale().raw().toBuffer();
 // Only terrain geometry is smoothed; no source artwork is deformed.
 road=await sharp(road,{raw:{width:W,height:H,channels:1}}).blur(9).greyscale().raw().toBuffer();
 const roadMask=Uint8Array.from(road,v=>v>=120?1:0);
 const waterMask=Uint8Array.from(water,v=>v>=128?1:0);
 const shore=new Float32Array(H);
 for(let y=0;y<H;y++){let x=W-1;while(x>W/2&&!waterMask[y*W+x])x--;if(x===W-1){while(x>W/2&&waterMask[y*W+x])x--;x++;}shore[y]=x;}
 // Smooth the lower handoff bank, retain the exact old-map shoreline endpoint.
 const smoothShore=new Float32Array(H);
 for(let y=0;y<H;y++){let sum=0,n=0;for(let d=-18;d<=18;d++){const yy=Math.max(0,Math.min(H-1,y+d));sum+=shore[yy];n++;}smoothShore[y]=sum/n;}
 let oldShore=1535;for(let x=1000;x<1536;x++)if(original[2].data[x*4+3]>128){oldShore=x;break;}
 for(let y=H-192;y<H;y++){const t=(y-(H-192))/191,s=t*t*(3-2*t);smoothShore[y]=smoothShore[H-193]*(1-s)+(1536+oldShore)*s;}
 for(let y=0;y<H;y++)for(let x=0;x<W;x++)waterMask[y*W+x]=x>=smoothShore[y]?1:0;
 // Brown shoreline rocks in the flattened guide were previously classified
 // as extra roads. The road network stays inland; the bank is painted below.
 for(let y=0;y<H;y++)for(let x=Math.max(0,Math.floor(smoothShore[y]-48));x<W;x++)roadMask[y*W+x]=0;
 const roadIn=distance(roadMask,W,H,true),roadOut=distance(roadMask,W,H,false);
 const layers=[fields[0],Buffer.alloc(W*H*4),Buffer.alloc(W*H*4),Buffer.alloc(W*H*4)];
 const terrainMask=new Uint8Array(W*H);
 for(let y=0;y<H;y++)for(let x=0;x<W;x++){
  const p=y*W+x,sd=roadMask[p]?roadIn[p]:-roadOut[p],jitter=(noise(x>>1,y>>1)-.5)*8+(fields[0][p*4+1]-100)*.055;
  if(sd+jitter>0){copy(layers[1],p,fields[1],p);terrainMask[p]=1;}
  const bankDistance=smoothShore[y]-x;
  const bankWidth=23+8*Math.sin(y/91)+5*Math.sin(y/37+1.3);
  if(bankDistance>0&&bankDistance<bankWidth+(noise(x>>1,y>>1)-.5)*7+(fields[0][p*4+1]-100)*.035){
   copy(layers[1],p,fields[1],p);terrainMask[p]=1;
   // Earth grows darker immediately beneath the water, with no warped rocks.
   const dark=bankDistance<5?.60:bankDistance<11?.78:.92;
   for(let k=0;k<3;k++)layers[1][p*4+k]=Math.round(layers[1][p*4+k]*dark);
  }
  if(waterMask[p]){copy(layers[2],p,fields[2],p);terrainMask[p]=2;}
 }
 // Match the original map at y=0 using native pixel samples. The transition
 // uses 1px stippling over 96px, never rectangles, resized strips or blur.
 for(let dy=0;dy<96;dy++)for(let x=0;x<1536;x++){
  const p=(H-1-dy)*W+1536+x,q=dy*original[0].info.width+x,prob=Math.pow(1-dy/96,1.5);
  for(let c=0;c<3;c++)if(original[c].data[q*4+3]===255&&terrainMask[p]===c&&noise(x,dy+999)<prob)copy(layers[c],p,original[c].data,q);
 }
 console.log('[Polish] Replacing damaged foreground sprites.');
 const polished=await polishObjects(manifest,{project:PROJECT,reportPath:path.join(POLISH,'object-replacement-report.json')});manifest=polished.manifest;
 manifest.border_visual_overrides=await polishBorderTrees({project:PROJECT});
 const {buildWallCap}=require('./wilderness/polish_wall_cap.cjs');
 manifest.objects.push(await buildWallCap({project:PROJECT}));
 const {paintGroundDetails}=require('./wilderness/polish_ground_details.cjs');
 const details=await paintGroundDetails({project:PROJECT,width:W,height:H,origin:manifest.map_origin,terrainMask,objects:manifest.objects});layers[3]=details.rgba;
 const {paintRiverbank}=require('./wilderness/polish_riverbank.cjs');
 const bank=await paintRiverbank({project:PROJECT,width:W,height:H,shore:smoothShore,terrainMask,rgba:layers[3]});layers[3]=bank.rgba;
 const entries=[];
 for(let i=0;i<4;i++){
  const name=['Grass','Paths','Water','GroundDetails'][i],cells=[],physics=[];
  for(let ty=0;ty<H/T;ty++)for(let tx=0;tx<W/T;tx++){
   let visible=false;for(let yy=0;yy<T&&!visible;yy++)for(let xx=0;xx<T;xx++)if(layers[i][((ty*T+yy)*W+tx*T+xx)*4+3]){visible=true;break;}
   if(!visible)continue;cells.push([tx-48,ty-96,tx,ty]);
   if(i===2){const polys=polygons(terrainMask,tx,ty);if(polys.length)physics.push({atlas:[tx,ty],polygons:polys});}
  }
  await write(layers[i],W,H,path.join(OUT,name+'.png'));
  const e={name,texture:'res://Assets/MapTiles/Wilderness/'+name+'.png',tile_size:T,z_index:i===3?-9:-10,cells,physics_cells:physics};
  if(i<3){const brush=Buffer.alloc(256*64*4);for(let k=0;k<16;k++){const s=pools[i].candidates[(k*73)%pools[i].candidates.length];for(let y=0;y<32;y++)for(let x=0;x<32;x++)copy(brush,((k>>3)*32+y)*256+(k%8)*32+x,pools[i].data,(s.y+y)*pools[i].width+s.x+x);}await write(brush,256,64,path.join(OUT,name+'Brushes.png'));Object.assign(e,{brush_texture:'res://Assets/MapTiles/Wilderness/'+name+'Brushes.png',brush_count:16,brush_collidable:i===2});}
  entries.push(e);
 }
 manifest.terrain=entries;
 manifest.verification.polish={method:'Native-scale texture quilting, continuous terrain masks, complete original-style sprites; no artwork warp.',texture_sample_counts:pools.map(p=>p.candidates.length),objects:polished.report,details:details.report,riverbank:bank.report,protected_files:before};
 fs.writeFileSync(path.join(OUT,'wilderness_manifest.json'),JSON.stringify(manifest));
 const preview=Buffer.from(layers[0]);
 for(let i=1;i<4;i++)for(let p=0;p<W*H;p++)if(layers[i][p*4+3])copy(preview,p,layers[i],p);
 await write(preview,W,H,path.join(POLISH,'terrain-after.png'));
 for(const o of [...manifest.objects].sort((a,b)=>a.foot[1]-b.foot[1])){const {data,info}=await rgba(path.join(PROJECT,o.texture.slice(6))),[wx,wy]=o.bbox;for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){const p=y*info.width+x,dx=wx+1536+x,dy=wy+3072+y;if(dx>=0&&dx<W&&dy>=0&&dy<H&&data[p*4+3])copy(preview,dy*W+dx,data,p);}}
 await write(preview,W,H,path.join(POLISH,'wilderness-after.png'));
 for(const[p,v]of Object.entries(before))if(hash(path.join(PROJECT,p))!==v)throw new Error('Protected map file changed: '+p);
 console.log('[Polish] Saved editable layers and manifest. Original map, collisions and camera sources unchanged.');
}
module.exports={main};
if(require.main===module)main().catch(e=>{console.error(e);process.exitCode=1;});
