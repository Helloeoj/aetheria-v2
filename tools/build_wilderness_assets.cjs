'use strict';

// Extract existing approved pixels into transparent source layers, then build
// editable terrain and object resources. Never rebuild the original map here.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const {extractWildernessObjects}=require('./wilderness/extract_wilderness_objects.cjs');
const {planSectionWarps,applyPixelMap}=require('./wilderness/align_wilderness_sections.cjs');
const PROJECT=path.resolve(__dirname,'../godot_client');
const INPUT=path.resolve(__dirname,'../art_sources/wilderness-v1');
const OUT=path.join(PROJECT,'Assets/MapTiles/Wilderness');
const LAYERS=path.join(PROJECT,'Assets/MapLayers/Wilderness');
const EXPORT=path.resolve(__dirname,'../../exports/WildernessIntegration_v1');
const S=1536,T=32,W=3072,H=3072,ORIGIN=[-1536,-3072];
const DEFINITIONS=[
 {id:'01',name:'Riverside Royal Road',file:'01-riverside-royal-road-v1.png',grid:[1,1]},
 {id:'02',name:'Woodland Transition',file:'02-woodland-transition-v1.png',grid:[1,0]},
 {id:'03',name:'Quiet Farm and Wheat Field',file:'03-quiet-farm-and-wheat-v2.png',grid:[0,1]},
 {id:'04',name:'Roadside Tavern',file:'04-roadside-tavern-v2.png',grid:[0,0]},
];
const SOURCE_LAYER_NAMES=['00_Grass','10_Paths','20_Water','25_GroundDetails','30_Buildings','40_Rocks','50_Trees','60_Wheat'];
const TERRAIN_NAMES=['Grass','Paths','Water','GroundDetails'];
const SHA=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const mkdir=p=>fs.mkdirSync(p,{recursive:true});
const read=async p=>sharp(p).ensureAlpha().raw().toBuffer({resolveWithObject:true});
const png=async(b,w,h,p)=>{mkdir(path.dirname(p));await sharp(b,{raw:{width:w,height:h,channels:4}}).png({compressionLevel:6}).toFile(p);};
function copyPixel(out,source,p,q){source.copy(out,p*4,q*4,q*4+4);}
function morph(mask,w,h,r,erode=false){
 const stride=w+1,ii=new Int32Array(stride*(h+1));
 for(let y=0;y<h;y++){let sum=0;for(let x=0;x<w;x++){sum+=mask[y*w+x]?1:0;ii[(y+1)*stride+x+1]=ii[y*stride+x+1]+sum;}}
 const out=new Uint8Array(w*h);
 for(let y=0;y<h;y++)for(let x=0;x<w;x++){const x0=Math.max(0,x-r),x1=Math.min(w,x+r+1),y0=Math.max(0,y-r),y1=Math.min(h,y+r+1);const n=ii[y1*stride+x1]-ii[y0*stride+x1]-ii[y1*stride+x0]+ii[y0*stride+x0];out[y*w+x]=erode?n===(x1-x0)*(y1-y0):n>0;}
 return out;
}
function keepLarge(mask,w,h,min){
 const out=new Uint8Array(mask.length),seen=new Uint8Array(mask.length),q=new Int32Array(mask.length);
 for(let p=0;p<mask.length;p++)if(mask[p]&&!seen[p]){let a=0,b=1;q[0]=p;seen[p]=1;while(a<b){const n=q[a++],x=n%w,y=n/w|0;for(const v of [x?n-1:-1,x<w-1?n+1:-1,y?n-w:-1,y<h-1?n+w:-1])if(v>=0&&mask[v]&&!seen[v]){seen[v]=1;q[b++]=v;}}if(b>=min)for(let i=0;i<b;i++)out[q[i]]=1;}
 return out;
}
function terrainLabels(data,w,h,owners,hasRiver){
 const labels=new Uint8Array(w*h),brown=new Uint8Array(w*h),waterStarts=new Int32Array(h);waterStarts.fill(w);
 const blue=p=>{const r=data[p*4],g=data[p*4+1],b=data[p*4+2];return b>r*1.18&&b>g*.96&&b>55;};
 for(let y=0;y<h;y++){
  if(hasRiver)for(let x=Math.floor(w*.58);x<w-10;x++){let n=0;for(let k=0;k<10;k++)if(blue(y*w+x+k))n++;if(n>=7){waterStarts[y]=x;break;}}
  for(let x=0;x<w;x++){const p=y*w+x,r=data[p*4],g=data[p*4+1],b=data[p*4+2];if(x>=waterStarts[y])labels[p]=2;else if(owners[p]<0&&r>g*1.08&&g>b*1.2&&r>55&&r-b>25)brown[p]=1;}
 }
 const road=keepLarge(morph(morph(brown,w,h,2),w,h,2,true),w,h,300),nearRoad=morph(road,w,h,7);
 for(let p=0;p<labels.length;p++){if(labels[p]===2)continue;const r=data[p*4],g=data[p*4+1],b=data[p*4+2];const stone=Math.max(r,g,b)-Math.min(r,g,b)<65&&r>90&&g>70;if(road[p]||(nearRoad[p]&&stone))labels[p]=1;}
 return labels;
}
function resizeIndex(sw,sh){const m=new Int32Array(S*S);for(let y=0;y<S;y++)for(let x=0;x<S;x++)m[y*S+x]=Math.min(sh-1,Math.floor((y+.5)*sh/S))*sw+Math.min(sw-1,Math.floor((x+.5)*sw/S));return m;}
function touchesJoin(o,def,sw,sh){
 if(!['Trees','GroundDetails','Rocks'].includes(o.kind))return false;
 const [x0,y0,x1,y1]=o.bounds;
 // Keep the short entry corridor clear while painting its curved connection
 // from real terrain patches; bending nearby foreground art would smear it.
 if(def.id==='01'&&x1>sw*820/S&&y1>sh*(S-384)/S)return true;
 if(o.kind==='GroundDetails'){
  const margin=sw*64/S;
  if((x0<margin&&def.grid[0]===1)||(x1>sw-margin&&def.grid[0]===0)||(y0<margin&&def.grid[1]===1)||(y1>sh-margin&&def.grid[1]===0)||(def.id==='01'&&y1>sh-margin))return true;
 }
 const edgeMargin=20;
 return (x0<=edgeMargin&&def.grid[0]===1)||(x1>=sw-edgeMargin&&def.grid[0]===0)||(y0<=edgeMargin&&def.grid[1]===1)||(y1>=sh-edgeMargin&&def.grid[1]===0)||(def.id==='01'&&y1>=sh-edgeMargin);
}
function classLayer(kind){return ({GroundDetails:3,Buildings:4,Rocks:5,Trees:6,Wheat:7})[kind];}
function worldOrigin(def){return [ORIGIN[0]+def.grid[0]*S,ORIGIN[1]+def.grid[1]*S];}
function polygonRects(mask,tx,ty){
 const active=new Map(),polys=[];
 for(let gy=0;gy<=8;gy++){
  const runs=[];let start=-1;
  if(gy<8)for(let gx=0;gx<=8;gx++){let solid=false;if(gx<8){let n=0;for(let yy=0;yy<4;yy++)for(let xx=0;xx<4;xx++)if(mask[(ty*T+gy*4+yy)*W+tx*T+gx*4+xx]===2)n++;solid=n>=8;}if(solid&&start<0)start=gx;if(!solid&&start>=0){runs.push([start,gx]);start=-1;}}
  const keys=new Set(runs.map(r=>r.join(',')));
  for(const[key,r]of active)if(!keys.has(key)){polys.push([[r.x0*4-16,r.y0*4-16],[r.x1*4-16,r.y0*4-16],[r.x1*4-16,gy*4-16],[r.x0*4-16,gy*4-16]]);active.delete(key);}
  for(const[x0,x1]of runs){const k=[x0,x1].join(',');if(!active.has(k))active.set(k,{x0,x1,y0:gy});}
 }
 return polys;
}
function noise(x,y){let n=Math.imul((x/3|0)+3,73856093)^Math.imul((y/3|0)+7,19349663);n^=n>>>16;return(n>>>0)/4294967296;}

async function main(){
 mkdir(OUT);mkdir(path.join(OUT,'Objects'));mkdir(LAYERS);mkdir(EXPORT);
 const preservedPaths=['scenes/EastOutskirtsBlockout.tscn','scenes/PlayableMapContent.tscn','Assets/MapTiles/map_manifest.json'];
 const preserved=Object.fromEntries(preservedPaths.map(p=>[p,SHA(path.join(PROJECT,p))]));
 const sources={},sectionRecords=[],layerReports=[];
 for(const def of DEFINITIONS){
  const file=path.join(INPUT,def.file),{data,info}=await read(file),extraction=extractWildernessObjects(data,info.width,info.height,def.id);
  const owner=new Int32Array(info.width*info.height);owner.fill(-1);
  extraction.objects.forEach((o,i)=>{for(const p of o.pixels)owner[p]=i;});
  const labels=terrainLabels(data,info.width,info.height,owner,Number(def.id)<3);
  // Export mutually exclusive original-pixel layers before join adjustment.
  const cutouts=SOURCE_LAYER_NAMES.map(()=>Buffer.alloc(data.length));
  for(let p=0;p<owner.length;p++){const o=owner[p]>=0?extraction.objects[owner[p]]:null;copyPixel(cutouts[o?classLayer(o.kind):labels[p]],data,p,p);}
  let different=0;for(let p=0;p<owner.length;p++){let n=0;for(const l of cutouts)if(l[p*4+3])n++;if(n!==1)different++;}
  if(different)throw new Error('Non-exclusive source cutouts in section '+def.id);
  const layerDirectory=path.join(LAYERS,'Section'+def.id);mkdir(layerDirectory);
  for(let i=0;i<cutouts.length;i++)await png(cutouts[i],info.width,info.height,path.join(layerDirectory,SOURCE_LAYER_NAMES[i]+'.png'));
  const index=resizeIndex(info.width,info.height);
  const resized=applyPixelMap(data,index,4),resizedOwner=applyPixelMap(owner,index,1),resizedLabels=applyPixelMap(labels,index,1);
  sources[def.id]={data:resized,rgba:resized,width:S,height:S,owner:resizedOwner,labels:resizedLabels,definition:def,extraction,sourceWidth:info.width,sourceHeight:info.height};
  layerReports.push({section:def.id,source:('art_sources/wilderness-v1/'+def.file),source_sha256:SHA(file),canvas:[info.width,info.height],layers:SOURCE_LAYER_NAMES.map(n=>'res://Assets/MapLayers/Wilderness/Section'+def.id+'/'+n+'.png'),original_pixel_partition:true});
  console.log('[Wilderness assets] Separated section '+def.id+': '+extraction.objects.length+' foreground objects.');
 }
 const oldLayers=[];for(const n of ['00_Ground','10_Paths','20_Water','30_WallsAndBuildings','40_Rocks','50_Vegetation'])oldLayers.push((await read(path.join(PROJECT,'Assets/MapLayers',n+'.png'))).data);
 const oldComposite=Buffer.alloc(1536*1024*4);for(const l of oldLayers)for(let p=0;p<1536*1024;p++)if(l[p*4+3])copyPixel(oldComposite,l,p,p);
 const warps=planSectionWarps(sources,{data:oldComposite,width:1536,height:1024});
 const terrain=TERRAIN_NAMES.map(()=>Buffer.alloc(W*H*4)),surface=new Uint8Array(W*H),objects=[],removed=[];
 let stitchPools=[];
 for(const def of DEFINITIONS){
  const src=sources[def.id],warp=warps[def.id],data=applyPixelMap(src.data,warp,4),owner=applyPixelMap(src.owner,warp,1),labels=applyPixelMap(src.labels,warp,1);
  const objectPixels=src.extraction.objects.map(()=>[]),[ox,oy]=worldOrigin(def),atlasX=def.grid[0]*S,atlasY=def.grid[1]*S;
  const drop=src.extraction.objects.map(o=>touchesJoin(o,def,src.sourceWidth,src.sourceHeight));
  const nearest=new Int32Array(S*S),queue=new Int32Array(S*S);nearest.fill(-1);let head=0,tail=0;
  for(let p=0;p<S*S;p++)if(owner[p]<0){nearest[p]=p;queue[tail++]=p;}
  while(head<tail){const p=queue[head++],x=p%S,y=p/S|0;for(const q of [x?p-1:-1,x<S-1?p+1:-1,y?p-S:-1,y<S-1?p+S:-1])if(q>=0&&nearest[q]<0){nearest[q]=nearest[p];labels[q]=labels[nearest[p]];queue[tail++]=q;}}
  const donors=[[],[],[]];
  for(let ty=0;ty<S;ty+=T)for(let tx=0;tx<S;tx+=T){let c=labels[ty*S+tx],ok=true;for(let y=0;y<T&&ok;y++)for(let x=0;x<T;x++){const p=(ty+y)*S+tx+x;if(owner[p]>=0||labels[p]!==c){ok=false;break;}}if(ok)donors[c].push([tx,ty]);}
  // Absence of an object mask alone does not guarantee an empty grass patch.
  // Rank out residual canopy shadows/highlights before filling hidden ground.
  const grassQuality=([tx,ty])=>{let bad=0;for(let y=0;y<T;y++)for(let x=0;x<T;x++){const q=((ty+y)*S+tx+x)*4,r=data[q],g=data[q+1],b=data[q+2];if(g<62||b>=22||r>g*1.02)bad++;}return bad;};
  donors[0].sort((a,b)=>grassQuality(a)-grassQuality(b));
  const clearGrass=donors[0].filter(p=>grassQuality(p)<=T*T*.025);
  donors[0]=(clearGrass.length?clearGrass:donors[0].slice(0,16)).slice(0,160);
  if(!donors[0].length)throw new Error('No clean grass backing patches in section '+def.id);
  if(def.id==='01')stitchPools=donors.map(pool=>pool.filter(d=>d[1]<S-416).map(d=>[d[0]+atlasX,d[1]+atlasY]));
  for(let p=0;p<S*S;p++){
   const x=p%S,y=p/S|0,g=(atlasY+y)*W+atlasX+x,oIndex=owner[p];let c=labels[p],q=p;
   if(oIndex>=0){
    const obj=src.extraction.objects[oIndex];
    if(obj.kind==='Wheat')c=0;
    const pool=donors[c].length?donors[c]:donors[0],d=pool[((x/T|0)*17+(y/T|0)*31)%pool.length];q=(d[1]+y%T)*S+d[0]+x%T;
    if(!drop[oIndex]){
     if(obj.kind==='GroundDetails')copyPixel(terrain[3],data,g,p);
     else objectPixels[oIndex].push(p);
    }
   }else if(c===0){
    const edge=Math.min(def.grid[0]===1?x:S-1-x,def.grid[1]===1?y:S-1-y,def.id==='01'?S-1-y:S);
    if(edge<64&&noise(x,y)<Math.pow(1-edge/64,1.2)){const pool=donors[0],d=pool[((x/T|0)*17+(y/T|0)*31)%pool.length];q=(d[1]+y%T)*S+d[0]+x%T;}
   }
   copyPixel(terrain[c],data,g,q);terrain[c][g*4+3]=255;surface[g]=c;
  }
  const transform=(point)=>{const a=warp.forwardPoint(point[0]*S/src.sourceWidth,point[1]*S/src.sourceHeight);return [Math.round(a[0])+ox,Math.round(a[1])+oy];};
  const make=async(sourceObj,pixels,suffix='')=>{
   if(!pixels.length)return;
   let minX=S,minY=S,maxX=-1,maxY=-1;for(const p of pixels){const x=p%S,y=p/S|0;minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
   const width=maxX-minX+1,height=maxY-minY+1,texture=Buffer.alloc(width*height*4);
   for(const p of pixels)copyPixel(texture,data,((p/S|0)-minY)*width+p%S-minX,p);
   let foot=transform(sourceObj.foot);
   if(sourceObj.kind==='Wheat')foot=[ox+minX+Math.floor(width/2),oy+maxY+1];
   const name=`Wilderness${def.id}_${sourceObj.kind}_${String(objects.length).padStart(4,'0')}${suffix}`;
   const filename=name+'.png';await png(texture,width,height,path.join(OUT,'Objects',filename));
   const complete=sourceObj.bounds[0]>20&&sourceObj.bounds[1]>20&&sourceObj.bounds[2]<src.sourceWidth-20&&sourceObj.bounds[3]<src.sourceHeight-20;
   const cell=foot.map(n=>Math.floor(n/T)),o={name,kind:sourceObj.kind,section:def.id,source_name:sourceObj.name,complete_source_object:complete,texture:'res://Assets/MapTiles/Wilderness/Objects/'+filename,cell,foot,bbox:[ox+minX,oy+minY,width,height],offset:foot.map((n,i)=>n-cell[i]*T-T/2),sprite_offset:[ox+minX-foot[0],oy+minY-foot[1]]};
   if(sourceObj.circles)o.collision_circles=sourceObj.circles.map(circle=>{const center=transform(circle.center),radius=circle.radius*S/src.sourceWidth;return {radius,position:center.map((n,i)=>n-foot[i])};});
   if(sourceObj.polygons)o.collision_polygons=sourceObj.polygons.map(poly=>poly.map(p=>transform(p).map((n,i)=>n-foot[i])));
   objects.push(o);
  };
  for(let i=0;i<src.extraction.objects.length;i++){
   const obj=src.extraction.objects[i];if(drop[i]){removed.push({section:def.id,name:obj.name,reason:'Truncated object at an interior section join; backed with terrain.'});continue;}
   if(obj.kind==='GroundDetails')continue;
   if(obj.kind==='Wheat'){
    // Crop plants are walkable, independently paintable rows of 32px patches.
    // Sorting each patch avoids hiding the complete actor behind one field.
    const bins=new Map();for(const p of objectPixels[i]){const key=(p%S/T|0)+','+((p/S|0)/T|0);if(!bins.has(key))bins.set(key,[]);bins.get(key).push(p);}
    for(const[key,pixels]of bins)await make(obj,pixels,'_Crop'+key.replace(',','_'));
   }else await make(obj,objectPixels[i]);
  }
  sectionRecords.push({id:def.id,name:def.name,origin:[ox,oy],size:[S,S],source:layerReports.find(r=>r.section===def.id).source,source_canvas:[src.sourceWidth,src.sourceHeight]});
  console.log('[Wilderness assets] Built editable content for section '+def.id+'.');
 }

 // Paint a gentle 384px approach from existing grass, road and water patches.
 // This avoids squeezing foreground rocks/trees into a sharp shoreline funnel.
 const corridorY=H-384,oldNorth=warps.measurements.existingMapNorth;
 const roadRuns=[];let run=-1,startShore=S;
 for(let x=820;x<=S;x++){const c=x<S?surface[(corridorY-1)*W+S+x]:-1;if(c===1&&run<0)run=x;if(c!==1&&run>=0){roadRuns.push([run,x]);run=-1;}if(c===2&&startShore===S)startShore=x;}
 const startRoad=roadRuns.sort((a,b)=>(b[1]-b[0])-(a[1]-a[0]))[0]||[980,1100];
 const startCenter=(startRoad[0]+startRoad[1])/2,startWidth=startRoad[1]-startRoad[0];
 const isBlue=q=>oldComposite[q*4+2]>oldComposite[q*4]*1.18&&oldComposite[q*4+2]>oldComposite[q*4+1]*.96;
 for(let y=corridorY;y<H;y++){
  const t=(y-corridorY)/(H-1-corridorY),smooth=t*t*(3-2*t),center=startCenter+(oldNorth.road.center-startCenter)*smooth,width=startWidth+(oldNorth.road.width-startWidth)*smooth;
  const shore=startShore+(oldNorth.water.start-startShore)*smooth,oldY=H-1-y;
  let oldShore=1535;for(let x=1050;x<1530;x++){let n=0;for(let k=0;k<6;k++)if(isBlue(oldY*S+x+k))n++;if(n>=4){oldShore=x;break;}}
  for(let x=820;x<S;x++){
   const p=y*W+S+x,jitter=(noise(x,y)-.5)*3*(1-smooth),c=x>=shore?2:Math.abs(x-center)<width/2+jitter?1:0;
   const available=stitchPools[c].length?stitchPools[c]:stitchPools[0],d=available[((x/T|0)*17+(y/T|0)*31)%available.length],q=(d[1]+y%T)*W+d[0]+x%T;
   for(const l of terrain)l.fill(0,p*4,p*4+4);
   copyPixel(terrain[c],terrain[c],p,q);surface[p]=c;
   if(x>=shore-44&&x<shore+10){const sx=Math.max(0,Math.min(S-1,Math.round(oldShore+x-shore)));copyPixel(terrain[c],oldComposite,p,oldY*S+sx);}
  }
 }

 // Blend only source-pixel terrain samples at the newly connected boundaries.
 // Every original map pixel and every existing collider remains untouched.
 function transfer(p,q,prob){const c=surface[p];if(c===surface[q]&&noise(p%W,p/W|0)<prob)copyPixel(terrain[c],terrain[c],p,q);}
 for(let d=0;d<64;d++){const prob=Math.pow(1-d/64,1.4);for(let y=0;y<H;y++)transfer(y*W+S-1-d,y*W+S+d,prob);for(let x=0;x<W;x++)transfer((S-1-d)*W+x,(S+d)*W+x,prob);}
 const oldTerrain=[];for(const n of ['Grass','PathsAndQuays','Water'])oldTerrain.push((await read(path.join(PROJECT,'Assets/MapTiles',n+'.png'))).data);
 for(let dy=0;dy<64;dy++)for(let x=0;x<S;x++){const p=(H-1-dy)*W+S+x,q=dy*S+x,c=surface[p];if(oldTerrain[c][q*4+3]===255&&noise(x,dy)<Math.pow(1-dy/64,1.2))copyPixel(terrain[c],oldTerrain[c],p,q);}

 // A small number of complete approved trees bridge former canvas boundaries.
 // Their art and trunk collision remain one movable scene tile.
 const treeCandidates=objects.filter(o=>o.kind==='Trees'&&o.complete_source_object&&((o.section==='01'&&o.source_name==='Tree_10')||(o.section==='04'&&o.source_name==='Tree_13')));
 const joinFeet=[[-15,-2790],[-10,-2100],[10,-1720],[5,-1190],[-15,-430],[5,-110],[-1160,-1470],[-280,-1470],[350,-1470],[670,-1470]];
 for(let i=0;i<joinFeet.length&&treeCandidates.length;i++){
  const src=treeCandidates[(i*7+3)%treeCandidates.length],foot=joinFeet[i],dx=foot[0]-src.foot[0],dy=foot[1]-src.foot[1],cell=foot.map(n=>Math.floor(n/T));
  objects.push({...src,name:'Wilderness_JoinTree_'+String(i+1).padStart(2,'0'),section:'join',cell,foot,bbox:[src.bbox[0]+dx,src.bbox[1]+dy,src.bbox[2],src.bbox[3]],offset:foot.map((n,k)=>n-cell[k]*T-T/2),join_reuse_of:src.name});
 }
 const terrainEntries=[];
 for(let s=0;s<terrain.length;s++){
  const name=TERRAIN_NAMES[s],cells=[],physics=[];
  for(let ty=0;ty<H/T;ty++)for(let tx=0;tx<W/T;tx++){
   let visible=false;for(let yy=0;yy<T&&!visible;yy++)for(let xx=0;xx<T;xx++)if(terrain[s][((ty*T+yy)*W+tx*T+xx)*4+3]){visible=true;break;}
   if(!visible)continue;cells.push([tx+ORIGIN[0]/T,ty+ORIGIN[1]/T,tx,ty]);
   if(s===2){const polygons=polygonRects(surface,tx,ty);if(polygons.length)physics.push({atlas:[tx,ty],polygons});}
  }
  await png(terrain[s],W,H,path.join(OUT,name+'.png'));
  const entry={name,texture:'res://Assets/MapTiles/Wilderness/'+name+'.png',tile_size:T,z_index:s===3?-9:-10,cells,physics_cells:physics};
  if(s<3){
   const candidates=[];for(let ty=0;ty<H/T;ty++)for(let tx=0;tx<W/T;tx++){let ok=true;for(let yy=0;yy<T&&ok;yy++)for(let xx=0;xx<T;xx++)if(terrain[s][((ty*T+yy)*W+tx*T+xx)*4+3]!==255){ok=false;break;}if(ok)candidates.push([tx*T,ty*T]);}
   if(candidates.length){const brushes=Buffer.alloc(256*64*4);for(let k=0;k<16;k++){const d=candidates[Math.floor(k*candidates.length/16)];for(let y=0;y<T;y++)for(let x=0;x<T;x++)copyPixel(brushes,terrain[s],((k/8|0)*T+y)*256+(k%8)*T+x,(d[1]+y)*W+d[0]+x);}await png(brushes,256,64,path.join(OUT,name+'Brushes.png'));entry.brush_texture='res://Assets/MapTiles/Wilderness/'+name+'Brushes.png';entry.brush_count=16;entry.brush_collidable=s===2;}
  }
  terrainEntries.push(entry);
 }
 const manifest={map_size:[W,H],map_origin:ORIGIN,section_size:S,sections:sectionRecords,terrain:terrainEntries,objects,verification:{approved_sections:layerReports,existing_preserved_files:preserved,seam_adjustment:'Source-pixel edge alignment, a 384px painted riverside entry corridor, terrain backing and 64px terrain joins; existing map not rebuilt.',removed_truncated_edge_objects:removed,object_counts:Object.fromEntries([...new Set(objects.map(o=>o.kind))].map(kind=>[kind,objects.filter(o=>o.kind===kind).length]))}};
 fs.writeFileSync(path.join(OUT,'wilderness_manifest.json'),JSON.stringify(manifest));
 fs.writeFileSync(path.join(EXPORT,'section-boundaries.json'),JSON.stringify(warps.measurements,null,2));
 fs.writeFileSync(path.join(EXPORT,'layer-export-report.json'),JSON.stringify(manifest.verification,null,2));
 const preview=Buffer.alloc(W*H*4);for(const layer of terrain)for(let p=0;p<W*H;p++)if(layer[p*4+3])copyPixel(preview,layer,p,p);
 for(const o of [...objects].sort((a,b)=>a.foot[1]-b.foot[1])){const b=(await read(path.join(PROJECT,o.texture.slice(6)))).data,[wx,wy,w,h]=o.bbox;for(let y=0;y<h;y++)for(let x=0;x<w;x++){const p=y*w+x,dx=wx-ORIGIN[0]+x,dy=wy-ORIGIN[1]+y;if(dx>=0&&dx<W&&dy>=0&&dy<H&&b[p*4+3])copyPixel(preview,b,dy*W+dx,p);}}
 await png(preview,W,H,path.join(EXPORT,'wilderness-layered-preview.png'));
 for(const[p,hash]of Object.entries(preserved))if(SHA(path.join(PROJECT,p))!==hash)throw new Error('Existing map source changed during conversion: '+p);
 console.log(JSON.stringify({manifest:path.join(OUT,'wilderness_manifest.json'),sections:4,sourceLayers:layerReports.length*SOURCE_LAYER_NAMES.length,terrainCells:terrainEntries.map(e=>[e.name,e.cells.length]),objects:manifest.verification.object_counts,existingMapPreserved:true},null,2));
}
// The original flattened-image extraction remains available for archival
// source-layer exports. Normal builds use complete sprites and native textures.
const build = process.argv.includes('--legacy-extraction') ? main : require('./polish_wilderness_assets.cjs').main;
build().catch(error=>{console.error(error.stack||error.message);process.exitCode=1;});
