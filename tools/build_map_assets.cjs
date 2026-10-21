'use strict';
// Convert approved artwork to paintable terrain patches and whole-object scene tiles.
// Original artwork and hand-authored collision sources are read-only inputs.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require('C:/Users/Riptide/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const {splitTreeComponent}=require('./split_map_trees.cjs');
const {warpHarborLayer,blendTerrainJoin}=require('./bridge_map_join.cjs');
const {applyCleanTreeOverrides}=require('./wilderness/apply_clean_tree_overrides.cjs');
const ROOT=path.resolve(__dirname,'../godot_client'), OUT=path.join(ROOT,'Assets/MapTiles');
const W=1536,H=2656,T=32,OLD_H=1024,CROP=675,NEW_H=1629;
fs.mkdirSync(path.join(OUT,'Objects'),{recursive:true});
const image=async p=>(await sharp(p).ensureAlpha().raw().toBuffer());
const canvas=()=>Buffer.alloc(W*H*4);
const terrain=[canvas(),canvas(),canvas(),canvas()];
const objects=[], objectPixels=new Uint8Array(W*H), boatPixels=new Uint8Array(W*H);
const sourceComposite=canvas(), verification={};
const oldTrunks=[[627,257],[530,207],[1015,132],[444,940],[1293,888],[577,992],[654,891],[293,741],[258,658],[253,998],[266,385],[255,283],[346,266],[1086,860],[636,416],[1069,188],[260,196]];
const oldRocks=[[1034,966],[1299,449],[1063,981]];
const rgba=(b,p)=>b.subarray(p*4,p*4+4);
const blockoutText=fs.readFileSync(path.join(ROOT,'scenes/EastOutskirtsBlockout.tscn'),'utf8');
const sections=blockoutText.split(/\r?\n(?=\[)/), authoredShapes={},authored=[];
let authoredWater=[];
for(const s of sections){
 const shape=s.match(/^\[sub_resource type="(RectangleShape2D|CircleShape2D)" id="([^"]+)"\]/);
 if(shape){const nums=s.match(/size = Vector2\(([^)]+)\)/);authoredShapes[shape[2]]=shape[1]==='CircleShape2D'?{radius:Number(s.match(/radius = ([\d.]+)/)?.[1]||20)}:{size:nums[1].split(',').map(Number)};}
 const node=s.match(/^\[node name="([^"]+)" type="(CollisionShape2D|CollisionPolygon2D)" parent="([^"]+)"\]/);
 if(node){const pos=(s.match(/position = Vector2\(([^)]+)\)/)?.[1]||'0,0').split(',').map(Number);
  if(node[2]==='CollisionPolygon2D'&&node[3]==='WaterCollision'){const a=s.match(/polygon = PackedVector2Array\(([^)]+)\)/)[1].split(',').map(Number);for(let i=0;i<a.length;i+=2)authoredWater.push([a[i]+pos[0],a[i+1]+pos[1]]);}
  else {const id=s.match(/shape = SubResource\("([^"]+)"\)/)?.[1];if(id)authored.push({name:node[1],kind:node[3],position:pos,...authoredShapes[id]});}
 }
}
function clipToCell(poly,x,y){
 let out=poly;for(const [axis,limit,sign] of [[0,x,1],[0,x+32,-1],[1,y,1],[1,y+32,-1]]){const input=out;out=[];for(let i=0;i<input.length;i++){const a=input[i],b=input[(i+1)%input.length],ina=(a[axis]-limit)*sign>=0,inb=(b[axis]-limit)*sign>=0;if(ina)out.push(a);if(ina!==inb){const t=(limit-a[axis])/(b[axis]-a[axis]);out.push([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])]);}}}
 let changed=true;while(changed&&out.length>=3){changed=false;for(let i=0;i<out.length;i++){const a=out[(i+out.length-1)%out.length],b=out[i],c=out[(i+1)%out.length];if(Math.hypot(a[0]-b[0],a[1]-b[1])<.001||Math.abs((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]))<.001){out.splice(i,1);changed=true;break;}}}
 if(out.length<3)return[];const area=Math.abs(out.reduce((s,p,i)=>s+p[0]*out[(i+1)%out.length][1]-p[1]*out[(i+1)%out.length][0],0));return area>0.01?out.map(p=>[p[0]-x-16,p[1]-y-16]):[];
}
function put(dst,src,s,p){src.copy(dst,p*4,s*4,s*4+4);}
function components(data,w,h){
 const visited=new Uint8Array(w*h),list=[];
 for(let p=0;p<w*h;p++)if(!visited[p]&&data[p*4+3]){
  const pixels=[p];visited[p]=1;let minX=p%w,maxX=minX,minY=(p/w)|0,maxY=minY;
  for(let i=0;i<pixels.length;i++){const q=pixels[i],x=q%w,y=(q/w)|0;minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);
   for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){const nx=x+dx,ny=y+dy;if(nx<0||nx>=w||ny<0||ny>=h)continue;const n=ny*w+nx;if(!visited[n]&&data[n*4+3]){visited[n]=1;pixels.push(n);}}
  }
  list.push({pixels,minX,maxX,minY,maxY,w:maxX-minX+1,h:maxY-minY+1});
 }
 return list;
}
async function extract(data,kind,region){
 let list=components(data,W,H);
 if(kind==='Trees'&&region==='Outskirts'){
  // A small bush beside a trunk may share its bounding rectangle. Assign each
  // authored anchor to one component before partitioning touching canopies.
  const owned=new Map(list.map(c=>[c,[]]));
  for(const a of oldTrunks){
   const score=c=>{const dx=Math.max(c.minX-a[0],0,a[0]-c.maxX),dy=Math.max(c.minY-a[1],0,a[1]-c.maxY);return dx*dx+dy*dy+Math.pow(c.maxY-a[1],2)*.01+Math.pow((c.minX+c.maxX)/2-a[0],2)*.01;};
   const owner=list.reduce((best,c)=>score(c)<score(best)?c:best,list[0]);
   owned.get(owner).push(a);
  }
  list=list.flatMap(c=>splitTreeComponent(c,owned.get(c),W));
 }
 for(const c of list){
  let actual=kind;
  const area=c.pixels.length;
  let isObject=kind==='Trees'?area>=650&&c.w>=32&&c.h>=38:kind==='Buildings'?area>=350&&c.w>=16&&c.h>=18:kind==='Rocks'?area>=55&&c.w>=8&&c.h>=8:kind==='Props'?area>=55&&c.w>=7&&c.h>=9:area>=400&&c.h>=15;
  if(kind==='Rocks'&&c.h>180&&c.h>c.w*2.5)isObject=false;
  if(kind==='Buildings'&&c.minX<260&&c.h>300)actual='Walls';
  // Cropped foliage from the repeated reference area is replaced with ground.
  if(region==='Harbor'&&kind==='Trees'&&c.minY===OLD_H){for(const p of c.pixels)objectPixels[p]=1;continue;}
  if(!isObject){for(const p of c.pixels)put(terrain[3],data,p,p);continue;}
  let footX=0,count=0;for(const p of c.pixels)if(((p/W)|0)>=c.maxY-Math.max(3,Math.floor(c.h*.08))){footX+=p%W;count++;}
  footX=count?Math.round(footX/count):Math.round((c.minX+c.maxX)/2);
  let footY=c.maxY-1;
  if(c.anchor){[footX,footY]=c.anchor;}
  const crop=Buffer.alloc(c.w*c.h*4);for(const p of c.pixels){const x=p%W,y=(p/W)|0;put(crop,data,p,(y-c.minY)*c.w+x-c.minX);objectPixels[p]=1;if(kind==='Boats')boatPixels[p]=1;}
  const name=`${region}_${actual}_${String(objects.length).padStart(3,'0')}`;
  await sharp(crop,{raw:{width:c.w,height:c.h,channels:4}}).png().toFile(path.join(OUT,'Objects',name+'.png'));
  const cell=[Math.floor(footX/T),Math.floor(footY/T)];
  const o={name,kind:actual,texture:`res://Assets/MapTiles/Objects/${name}.png`,cell,offset:[footX-cell[0]*T-16,footY-cell[1]*T-16],sprite_offset:[c.minX-footX,c.minY-footY],bbox:[c.minX,c.minY,c.w,c.h],foot:[footX,footY],source:region};
  const existingTree=kind==='Trees'&&region==='Outskirts'&&Boolean(c.anchor);
  const existingRock=kind==='Rocks'&&region==='Outskirts'&&oldRocks.some(([x,y])=>x>=c.minX-10&&x<=c.maxX+10&&y>=c.minY-10&&y<=c.maxY+20);
  if(actual==='Trees'&&!existingTree){const r=Math.max(7,Math.min(24,c.w*.095));o.collision_circle={radius:r,position:[0,-r*.35]};}
  else if(actual==='Rocks'&&!existingRock){const hw=c.w*.38,hh=Math.min(c.h*.34,25);o.collision_polygons=[[[-hw,-hh*1.6],[hw,-hh*1.6],[hw,0],[-hw,0]]];}
  else if(actual==='Props'){const hw=c.w*.37,hh=c.h*.45;o.collision_polygons=[[[-hw,-hh],[hw,-hh],[hw,0],[-hw,0]]];}
  else if(actual==='Buildings'){
   // Buildings use a footprint below the roof, leaving space to walk behind it.
   const left=c.minX-footX+c.w*.08,right=c.maxX-footX-c.w*.08,back=-c.h*.34;
   o.collision_polygons=[[[left,back],[right,back],[right,0],[left,0]]];
  }else if(actual==='Walls'&&region==='Harbor'){
   const left=c.minX-footX,right=c.maxX-footX;o.collision_polygons=[[[left,-c.h],[right,-c.h],[right,0],[left,0]]];
  }
  objects.push(o);
 }
}
async function main(){
 const oldNames=['00_Ground','10_Paths','20_Water','30_WallsAndBuildings','40_Rocks','50_Vegetation'];
 for(let i=0;i<oldNames.length;i++){
  const p=path.join(ROOT,'Assets/MapLayers',oldNames[i]+'.png'),b=await image(p),global=canvas();b.copy(global);
  verification[oldNames[i]]=crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
  for(let q=0;q<W*OLD_H;q++)if(global[q*4+3])put(sourceComposite,global,q,q);
  if(i<3)b.copy(terrain[i]);else await extract(global,['Buildings','Rocks','Trees'][i-3],'Outskirts');
 }
 const hn=['00_Ground','10_PathsAndQuays','20_Water','30_WallsAndBuildings','35_DocksAndCranes','40_Rocks','50_Vegetation','60_Boats','70_CargoAndProps'];
 for(let i=0;i<hn.length;i++){
  const harborImage=sharp(path.join(ROOT,'Assets/MapLayers/CapitalHarbor',hn[i]+'.png')).resize(W,2304,{kernel:'nearest'});
  const b=await harborImage.clone().extract({left:0,top:CROP,width:W,height:NEW_H}).ensureAlpha().raw().toBuffer(),global=canvas();b.copy(global,W*OLD_H*4);
  warpHarborLayer(global,W,H,OLD_H);
  if(i===3){
   // Finish the tower and curtain facade clipped by the original canvas edge.
   // This approved facade sits below matching battlements later in the harbor
   // source; retain the south wall/tower in its approved position underneath.
   const wall=components(global,W,H).find(c=>c.minX===0&&c.w<260&&c.h>300);
   if(!wall)throw new Error('Cannot locate the harbor wall continuation');
   const joinHeight=159;
   for(const p of wall.pixels)if((p/W|0)<OLD_H+joinHeight)global.fill(0,p*4,p*4+4);
   const facade=await sharp(await harborImage.clone().toBuffer()).extract({left:0,top:1040,width:236,height:joinHeight}).resize(226,joinHeight,{kernel:'nearest'}).ensureAlpha().raw().toBuffer();
   for(let yy=0;yy<joinHeight;yy++)for(let xx=0;xx<226;xx++){const q=yy*226+xx;if(facade[q*4+3])put(global,facade,q,(OLD_H+yy)*W+xx);}
  }
  for(let q=W*OLD_H;q<W*(OLD_H+NEW_H);q++)if(global[q*4+3])put(sourceComposite,global,q,q);
  if(i<3||i===4){for(let q=W*OLD_H;q<W*(OLD_H+NEW_H);q++)if(global[q*4+3])put(terrain[i===4?1:i],global,q,q);}
  else await extract(global,({3:'Buildings',5:'Rocks',6:'Trees',7:'Boats',8:'Props'})[i],'Harbor');
 }
 // Build a filled terrain backing so moving/painting object tiles leaves usable terrain.
 const nearest=new Int32Array(W*H);nearest.fill(-1);const cls=new Uint8Array(W*H),queue=new Int32Array(W*H);let head=0,tail=0;
 for(let p=0;p<W*H;p++)for(let s=0;s<3;s++)if(terrain[s][p*4+3]){nearest[p]=p;cls[p]=s;queue[tail++]=p;break;}
 while(head<tail){const p=queue[head++],x=p%W,y=(p/W)|0;for(const n of [x? p-1:-1,x<W-1?p+1:-1,y?p-W:-1,y<H-1?p+W:-1])if(n>=0&&nearest[n]===-1){nearest[n]=nearest[p];cls[n]=cls[p];queue[tail++]=n;}}
 const donors=[[],[],[]];
 for(let s=0;s<3;s++)for(let ty=0;ty<H-T;ty+=T)for(let tx=0;tx<W;tx+=T){let ok=true;for(let y=0;y<T&&ok;y++)for(let x=0;x<T;x++)if(!terrain[s][((ty+y)*W+tx+x)*4+3]){ok=false;break;}if(ok)donors[s].push([tx,ty]);}
 const donorPools=donors.map(pool=>[pool.filter(d=>d[1]<OLD_H),pool.filter(d=>d[1]>=OLD_H)]);
 for(let p=0;p<W*H;p++){
  if(terrain[0][p*4+3]||terrain[1][p*4+3]||terrain[2][p*4+3])continue;
  let s=boatPixels[p]?2:cls[p],q=nearest[p];const x=p%W,y=(p/W)|0;
  const regionDonors=donorPools[s][y<OLD_H?0:1];
  const pool=regionDonors.length?regionDonors:donors[s];
  if(pool.length){const d=pool[((x/T|0)*17+(y/T|0)*31)%pool.length];q=(d[1]+y%T)*W+d[0]+x%T;}
  if(q<0)continue;put(terrain[s],terrain[s],q,p);if(!terrain[s][p*4+3]){const n=nearest[p];put(terrain[s],terrain[cls[p]],n,p);}terrain[s][p*4+3]=255;cls[p]=s;
 }
 // The final three padding rows continue the bank/water rather than an empty strip.
 for(let y=2653;y<H;y++)for(let x=0;x<W;x++){const p=y*W+x,q=2652*W+x;for(let s=0;s<3;s++)put(terrain[s],terrain[s],q,p);cls[p]=cls[q];}
 // Crisp source-pixel terrain transition; original 1536x1024 stays exact.
 blendTerrainJoin(terrain,cls,W,H,OLD_H);
 // Keep authored shapes byte-for-byte in the reference scene, and reproduce their
 // exact dimensions/positions in the corresponding movable scene tiles.
 for(const shape of authored){const kind=shape.kind==='TreeTrunkCollision'?'Trees':shape.kind==='RockCollision'?'Rocks':'Walls';
  const candidates=objects.filter(o=>o.source==='Outskirts'&&o.kind===kind);
  candidates.sort((a,b)=>{const score=o=>{const [x,y,w,h]=o.bbox,px=shape.position[0],py=shape.position[1];const dx=Math.max(x-px,0,px-x-w),dy=Math.max(y-py,0,py-y-h);return dx*dx+dy*dy+Math.hypot(px-o.foot[0],py-o.foot[1])*.01;};return score(a)-score(b);});
  const o=candidates[0];if(!o)throw new Error('No object for authored shape '+shape.name);
  if(!o.authored_collision){delete o.collision_circle;delete o.collision_polygons;o.authored_collision=[];}
  const [x,y]=shape.position.map((p,i)=>p-o.foot[i]);
  if(shape.radius){(o.collision_circles??=[]).push({radius:shape.radius,position:[x,y],authored_name:shape.name});}
  else {const [hw,hh]=shape.size.map(n=>n/2);(o.collision_polygons??=[]).push([[x-hw,y-hh],[x+hw,y-hh],[x+hw,y+hh],[x-hw,y+hh]]);}
  o.authored_collision.push(shape);
 }
 const manifest={map_size:[W,H],terrain:[],objects,verification:{blockout_sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,'scenes/EastOutskirtsBlockout.tscn'))).digest('hex'),original_assets:verification,authored_shapes_migrated:authored.length,authored_water_polygon:authoredWater}};
 for(let s=0;s<4;s++){
  const name=['Grass','PathsAndQuays','Water','GroundDetails'][s],texture=`res://Assets/MapTiles/${name}.png`,cells=[],physics=[];
  for(let ty=0;ty<H/T;ty++)for(let tx=0;tx<W/T;tx++){
   let visible=false;for(let y=0;y<T&&!visible;y++)for(let x=0;x<T;x++)if(terrain[s][((ty*T+y)*W+tx*T+x)*4+3]){visible=true;break;}
   if(!visible)continue;cells.push([tx,ty,tx,ty]);
   if(s===2&&ty*T>=OLD_H){
    // Four-pixel rectangles follow the shoreline, leave piers clear, and fill water under boats.
    const rows=[];for(let gy=0;gy<8;gy++){const runs=[];let start=-1;for(let gx=0;gx<=8;gx++){let solid=false;if(gx<8){let n=0;for(let yy=0;yy<4;yy++)for(let xx=0;xx<4;xx++){const p=(ty*T+gy*4+yy)*W+tx*T+gx*4+xx;if(cls[p]===2)n++;}solid=n>=7;}if(solid&&start<0)start=gx;if(!solid&&start>=0){runs.push([start,gx]);start=-1;}}rows.push(runs);}
    const polys=[];const active=new Map();for(let gy=0;gy<=8;gy++){const runs=gy<8?rows[gy]:[],keys=new Set(runs.map(r=>r.join(',')));for(const [key,r] of active)if(!keys.has(key)){polys.push([[r.x0*4-16,r.y0*4-16],[r.x1*4-16,r.y0*4-16],[r.x1*4-16,gy*4-16],[r.x0*4-16,gy*4-16]]);active.delete(key);}for(const [x0,x1] of runs){const key=[x0,x1].join(',');if(!active.has(key))active.set(key,{x0,x1,y0:gy});}}
    if(polys.length)physics.push({atlas:[tx,ty],polygons:polys});
   }
  }
  if(s===2){const used=new Set(cells.map(c=>c[0]+','+c[1]));for(let ty=0;ty<=32;ty++)for(let tx=0;tx<48;tx++){const poly=clipToCell(authoredWater,tx*32,ty*32);if(poly.length){const existing=physics.find(p=>p.atlas[0]===tx&&p.atlas[1]===ty);if(existing)existing.polygons.push(poly);else physics.push({atlas:[tx,ty],polygons:[poly]});const key=tx+','+ty;if(!used.has(key)){cells.push([tx,ty,tx,ty]);used.add(key);}}}}
  await sharp(terrain[s],{raw:{width:W,height:H,channels:4}}).png().toFile(path.join(OUT,name+'.png'));
  const entry={name,texture,tile_size:T,z_index:s===3?-9:-10,cells,physics_cells:physics};
  if(s<3&&donors[s].length){const brush=Buffer.alloc(256*64*4);for(let i=0;i<16;i++){const d=donors[s][Math.floor(i*donors[s].length/16)];for(let yy=0;yy<32;yy++)for(let xx=0;xx<32;xx++)put(brush,terrain[s],(d[1]+yy)*W+d[0]+xx,((i/8|0)*32+yy)*256+(i%8)*32+xx);}await sharp(brush,{raw:{width:256,height:64,channels:4}}).png().toFile(path.join(OUT,name+'Brushes.png'));entry.brush_texture=`res://Assets/MapTiles/${name}Brushes.png`;entry.brush_count=16;entry.brush_collidable=s===2;}
  manifest.terrain.push(entry);
 }
 const preview=Buffer.alloc(W*H*4);for(const b of terrain)for(let p=0;p<W*H;p++)if(b[p*4+3])put(preview,b,p,p);
 for(const o of objects){const b=await image(path.join(ROOT,o.texture.slice(6))),[x,y,w,h]=o.bbox;for(let yy=0;yy<h;yy++)for(let xx=0;xx<w;xx++){const p=yy*w+xx;if(b[p*4+3])put(preview,b,p,(y+yy)*W+x+xx);}}
 let differs=0;for(let p=0;p<W*OLD_H;p++)if(!rgba(preview,p).equals(rgba(sourceComposite,p)))differs++;
 manifest.verification.original_reference_different_pixels=differs;
 manifest.verification.object_counts=Object.fromEntries([...new Set(objects.map(o=>o.kind))].map(k=>[k,objects.filter(o=>o.kind===k).length]));
 fs.writeFileSync(path.join(OUT,'map_manifest.json'),JSON.stringify(manifest));
 const exportDir=path.resolve(ROOT,'../../exports/CapitalHarborLayers_v1');fs.mkdirSync(exportDir,{recursive:true});
 await sharp(preview,{raw:{width:W,height:H,channels:4}}).png().toFile(path.join(exportDir,'playable_map_preview.png'));
 console.log(JSON.stringify({objects:manifest.verification.object_counts,originalDifferentPixels:differs,terrainCells:manifest.terrain.map(t=>[t.name,t.cells.length,t.physics_cells.length])},null,2));
 if(differs)throw new Error('Original map pixel preservation failed');
 // The archival preview and source-pixel check above describe the unchanged
 // approved reference. Reapply reviewed production tree/grass PNGs afterwards.
 const reviewedOverrides=applyCleanTreeOverrides({projectRoot:ROOT});
 console.log(JSON.stringify({reviewedArtOverrides:reviewedOverrides},null,2));
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
