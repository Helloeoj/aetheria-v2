'use strict';

// These masks only choose existing source pixels. They never generate or recolor art.
// All measurements below are in the 1254 px approved preview coordinate system.
const REFERENCE_SIZE = 1254;
const CLASSES = { Trees: 1, Rocks: 2, Buildings: 3, Wheat: 4, GroundDetails: 5 };

const AREAS = {
  '01': {
    trees: [
      [0,0,143,158,48,151], [145,0,441,207,292,193], [469,17,669,187,575,174],
      [0,163,206,349,103,333], [304,252,492,389,407,377], [522,190,803,434,661,419],
      [203,364,437,552,320,540], [356,426,534,570,449,558], [925,445,1114,623,1017,607],
      [63,615,351,861,210,847], [519,662,802,894,674,875], [0,908,276,1145,124,1130],
      [471,852,627,1045,567,1024], [947,1012,1116,1148,1037,1133], [248,1103,549,1254,400,1253],
      [0,355,91,445,46,430], [195,264,263,340,228,328], [329,181,413,255,373,244],
      [587,541,662,619,629,608], [957,700,1032,791,995,777], [973,801,1062,894,1015,879],
      [731,859,859,964,793,951], [648,1058,739,1145,694,1132], [563,1154,644,1243,606,1228],
      [279,1037,354,1119,321,1109], [377,913,441,987,409,974], [0,780,82,894,39,883],
      [0,711,67,784,24,776], [0,567,115,687,45,675], [895,393,977,477,941,465],
      [863,494,953,581,907,571], [946,939,1020,1023,982,1012],
    ],
    rocks: [[438,155,508,210], [724,384,794,445], [426,535,481,586], [334,770,397,829], [703,949,780,1011], [939,1115,1009,1170], [954,598,1006,650], [992,344,1068,401], [965,163,1067,243]],
  },
  '02': {
    trees: [
      [0,0,201,154,93,143], [106,80,330,239,219,227], [0,132,139,286,35,274],
      [320,0,486,88,418,78], [381,53,559,177,472,168], [765,0,970,83,866,74],
      [16,268,269,491,137,478], [459,272,643,396,550,387], [549,125,754,338,647,326],
      [904,309,1145,503,1023,487], [472,414,667,600,568,584], [193,392,328,525,278,512],
      [773,492,964,649,875,633], [0,549,187,719,55,702], [78,551,191,659,136,647],
      [0,691,108,826,45,812], [246,592,486,828,367,814], [219,815,368,970,297,955],
      [541,858,753,1030,651,1009], [847,750,1069,945,955,925], [28,914,256,1119,147,1106],
      [0,1121,191,1254,102,1253], [376,960,693,1198,534,1180],
      [154,575,239,660,196,650], [484,755,574,844,525,832], [493,645,572,718,532,707],
      [919,594,1011,693,962,680], [801,664,904,755,857,742], [730,608,808,683,773,672],
      [393,822,471,912,436,900], [183,785,258,865,222,854], [280,985,349,1064,315,1052],
      [185,1068,275,1145,234,1135], [331,1055,402,1135,369,1122], [654,1076,744,1158,698,1148],
      [741,1123,820,1206,782,1193], [918,1085,1002,1170,960,1159], [919,963,1006,1046,963,1036],
      [601,843,695,930,649,920], [553,5,633,92,591,81], [437,223,513,291,476,281],
      [312,264,390,339,352,328], [84,215,173,289,127,278], [171,52,251,128,213,116],
    ],
    rocks: [[304,443,383,513], [325,943,377,981], [658,945,737,1015], [972,945,1023,991], [1001,1082,1059,1145], [1054,765,1104,821], [1035,634,1094,691], [1064,540,1124,608], [1062,218,1120,285]],
  },
  '03': {
    trees: [
      [0,0,229,210,113,196], [158,0,291,65,240,48], [278,0,464,165,382,148],
      [437,88,590,252,534,239], [449,0,516,58,477,44], [690,0,777,99,735,86],
      [780,0,966,66,897,52], [1020,0,1254,154,1137,139],
      [0,290,143,438,58,426], [301,267,538,463,435,448], [657,91,803,228,738,212],
      [758,89,999,309,859,296], [692,230,855,381,772,365], [951,253,1114,430,1048,418],
      [808,361,1024,563,923,548], [1160,153,1254,344,1223,332], [1154,358,1254,488,1224,476],
      [523,639,775,868,643,850], [14,824,262,1051,141,1036], [0,934,97,1117,40,1105],
      [461,965,609,1103,510,1087], [745,1030,897,1182,824,1166], [826,1072,968,1210,901,1195],
      [936,899,1150,1132,1042,1117], [1033,757,1254,991,1156,974], [0,1092,211,1254,91,1235],
      [277,1090,513,1254,395,1253], [1090,1092,1254,1254,1218,1237],
      [147,163,224,239,186,226], [94,208,174,281,139,269], [192,325,264,401,228,389],
      [180,418,257,493,218,481], [271,424,345,505,307,491], [327,389,402,474,363,462],
      [498,414,569,497,536,485], [604,467,678,545,643,532], [651,511,736,587,694,577],
      [899,530,982,616,940,604], [1016,505,1093,584,1054,573], [1080,664,1154,742,1117,731],
      [959,659,1036,736,997,724], [744,749,831,834,787,823], [740,855,822,938,784,926],
      [448,838,524,922,486,910], [368,1023,445,1102,408,1091], [276,958,357,1040,319,1027],
      [549,1020,618,1103,583,1090], [1131,989,1214,1074,1173,1064],
    ],
    rocks: [[181,201,262,265], [1020,133,1093,190], [1117,461,1173,519], [444,1103,519,1176], [503,1161,560,1207]],
    buildings: [{name:'Farmhouse', polygon:[[357,514],[361,492],[414,455],[458,477],[481,475],[481,461],[496,453],[523,461],[523,500],[533,527],[528,543],[524,606],[497,620],[480,626],[455,628],[437,615],[405,609],[365,582]], foot:[453,619], footprint:[[367,552],[422,534],[525,558],[524,606],[480,626],[405,609],[367,582]]}],
    wheat: [[[39,709],[194,584],[287,612],[550,744],[547,771],[397,946],[278,886],[62,778]]],
  },
  '04': {
    trees: [
      [0,0,168,177,48,165], [110,0,406,265,253,249], [305,0,434,62,378,49],
      [492,0,692,157,595,144], [610,0,774,64,698,49], [1011,0,1254,138,1147,123],
      [783,57,1082,312,918,298], [290,218,473,354,399,337], [405,263,585,406,481,391],
      [14,266,257,493,128,477], [1047,253,1254,474,1154,456],
      [18,599,315,875,150,856], [422,767,674,1023,541,1007], [847,776,1111,1008,984,993],
      [0,944,298,1204,158,1184], [737,1070,940,1232,831,1216], [1021,1011,1254,1206,1147,1187],
      [422,436,493,512,458,502], [325,500,398,573,359,562], [259,343,337,422,298,410],
      [682,162,764,244,722,233], [974,366,1049,447,1011,434], [1116,472,1199,552,1157,540],
      [574,541,646,610,611,600], [488,548,563,615,526,606], [737,676,861,790,801,775],
      [969,676,1046,755,1009,743], [1127,750,1204,832,1167,820], [1119,877,1207,961,1164,949],
      [787,950,871,1027,830,1016], [925,1027,1004,1115,964,1102], [370,1060,448,1145,411,1132],
      [302,1059,378,1140,341,1127], [348,930,423,1014,387,1003], [244,894,323,973,283,960],
      [344,681,419,763,386,751], [410,749,476,804,444,797], [7,600,82,677,43,665],
    ],
    rocks: [[333,383,425,455], [1120,163,1210,232], [1045,728,1120,793], [64,875,132,939], [332,1123,398,1181]],
    buildings: [{name:'RoyalRoadTavern', polygon:[[602,398],[614,342],[653,259],[708,267],[814,286],[816,280],[833,272],[854,280],[854,328],[895,375],[888,390],[883,468],[853,496],[831,504],[830,523],[811,529],[789,526],[783,518],[764,532],[731,535],[705,521],[677,510],[614,483]], foot:[751,529], footprint:[[615,405],[760,428],[881,399],[883,468],[851,496],[791,518],[761,532],[705,521],[615,483]]}],
  },
};

function sectionKey(value) {
  const match = String(value).match(/(?:^|\D)(0?[1-4])(?:\D|$)/);
  if (!match) throw new Error('Unknown wilderness section: ' + value);
  return match[1].padStart(2,'0');
}

function pointInPolygon(x,y,poly) {
  let inside=false;
  for(let i=0,j=poly.length-1;i<poly.length;j=i++) {
    const a=poly[i], b=poly[j];
    if(((a[1]>y)!==(b[1]>y)) && x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]) inside=!inside;
  }
  return inside;
}

function components(mask,width,height,min=1) {
  const seen=new Uint8Array(mask.length), output=[], queue=new Int32Array(mask.length);
  for(let p=0;p<mask.length;p++) {
    if(!mask[p]||seen[p])continue;
    let read=0,write=1; queue[0]=p;seen[p]=1;
    while(read<write) {
      const n=queue[read++],x=n%width,y=(n/width)|0;
      for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++) {
        if(!dx&&!dy)continue; const xx=x+dx,yy=y+dy;
        if(xx<0||xx>=width||yy<0||yy>=height)continue;
        const k=yy*width+xx;if(mask[k]&&!seen[k]){seen[k]=1;queue[write++]=k;}
      }
    }
    if(write>=min)output.push(Int32Array.from(queue.subarray(0,write)));
  }
  return output;
}

function dilate(mask,width,height,radius) {
  const result=new Uint8Array(mask.length);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++)if(mask[y*width+x]) {
    for(let dy=-radius;dy<=radius;dy++)for(let dx=-radius;dx<=radius;dx++) {
      const xx=x+dx,yy=y+dy;if(xx>=0&&xx<width&&yy>=0&&yy<height)result[yy*width+xx]=1;
    }
  }
  return result;
}

function erode(mask,width,height,radius) {
  const result=new Uint8Array(mask.length);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
    let valid=true;
    for(let dy=-radius;dy<=radius&&valid;dy++)for(let dx=-radius;dx<=radius;dx++) {
      const xx=x+dx,yy=y+dy;if(xx>=0&&xx<width&&yy>=0&&yy<height&&!mask[yy*width+xx]){valid=false;break;}
    }
    if(valid)result[y*width+x]=1;
  }
  return result;
}

function fillHoles(mask,width,height) {
  const outside=new Uint8Array(mask.length),queue=new Int32Array(mask.length);let read=0,write=0;
  function visit(p){if(!mask[p]&&!outside[p]){outside[p]=1;queue[write++]=p;}}
  for(let x=0;x<width;x++){visit(x);visit((height-1)*width+x);}
  for(let y=0;y<height;y++){visit(y*width);visit(y*width+width-1);}
  while(read<write){const p=queue[read++],x=p%width,y=(p/width)|0;if(x)visit(p-1);if(x+1<width)visit(p+1);if(y)visit(p-width);if(y+1<height)visit(p+width);}
  const result=new Uint8Array(mask);for(let p=0;p<mask.length;p++)if(!outside[p])result[p]=1;return result;
}

function boundsFor(pixels,width) {
  let x0=width,y0=Infinity,x1=0,y1=0;
  for(const p of pixels){const x=p%width,y=(p/width)|0;x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);}
  return [x0,y0,x1+1,y1+1];
}

function extractWildernessObjects(rgba,width,height,sectionId) {
  if(rgba.length!==width*height*4)throw new Error('RGBA buffer dimensions mismatch');
  const key=sectionKey(sectionId), spec=AREAS[key],sx=width/REFERENCE_SIZE,sy=height/REFERENCE_SIZE;
  const scalePoint=p=>[p[0]*sx,p[1]*sy];
  const classMask=new Uint8Array(width*height), foregroundMask=new Uint8Array(width*height),objects=[];
  const reserved=new Uint8Array(width*height);
  function polygonPixels(poly) {
    poly=poly.map(scalePoint);
    const minX=Math.max(0,Math.floor(Math.min(...poly.map(p=>p[0])))),maxX=Math.min(width-1,Math.ceil(Math.max(...poly.map(p=>p[0]))));
    const minY=Math.max(0,Math.floor(Math.min(...poly.map(p=>p[1])))),maxY=Math.min(height-1,Math.ceil(Math.max(...poly.map(p=>p[1]))));
    const pixels=[];
    for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++)if(pointInPolygon(x+.5,y+.5,poly))pixels.push(y*width+x);
    return Int32Array.from(pixels);
  }
  function add(kind,pixels,foot,extras={}) {
    if(!pixels.length)return;
    const clean=[];
    for(const p of pixels)if(!foregroundMask[p]){clean.push(p);foregroundMask[p]=1;classMask[p]=CLASSES[kind];}
    if(!clean.length)return;
    const bounds=boundsFor(clean,width);
    const touchesEdge=bounds[0]<=1||bounds[1]<=1||bounds[2]>=width-1||bounds[3]>=height-1;
    const object={kind,pixels:Int32Array.from(clean),foot,bounds,touchesEdge,...extras};
    objects.push(object);return object;
  }
  for(const b of spec.buildings||[]) {
    const pixels=polygonPixels(b.polygon);for(const p of pixels)reserved[p]=1;
    add('Buildings',pixels,scalePoint(b.foot),{name:b.name,polygons:[b.footprint.map(scalePoint)]});
  }
  for(const poly of spec.wheat||[]) {
    const pixels=polygonPixels(poly);for(const p of pixels)reserved[p]=1;
    const bounds=boundsFor(pixels,width);
    add('Wheat',pixels,[(bounds[0]+bounds[2])/2,bounds[3]],{name:'WheatField',walkable:true});
  }

  // Reserve boulders before classifying the surrounding foliage. Gray stone
  // patches inside a grove therefore stay independently movable/collidable.
  for(const box of spec.rocks||[]) {
    const x0=Math.max(0,Math.floor(box[0]*sx)),y0=Math.max(0,Math.floor(box[1]*sy)),x1=Math.min(width,Math.ceil(box[2]*sx)),y1=Math.min(height,Math.ceil(box[3]*sy));
    const rw=x1-x0,rh=y1-y0,mask=new Uint8Array(rw*rh);
    for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++) {
      const p=y*width+x,q=p*4,r=rgba[q],g=rgba[q+1],b=rgba[q+2];
      if(!foregroundMask[p]&&b>r*.38&&r>g*.87&&b<r*1.17)mask[(y-y0)*rw+x-x0]=1;
    }
    const close=erode(dilate(mask,rw,rh,1),rw,rh,1),parts=components(close,rw,rh,30),pixels=[];
    for(const part of parts)for(const p of part)pixels.push((y0+((p/rw)|0))*width+x0+p%rw);
    if(pixels.length<70)continue;const bounds=boundsFor(pixels,width),foot=[(bounds[0]+bounds[2])/2,bounds[3]-2*sy];
    add('Rocks',pixels,foot,{name:'Boulder',circles:[{center:[foot[0],foot[1]-5*sy],radius:Math.min((bounds[2]-bounds[0])*.28,(bounds[3]-bounds[1])*.32)}]});
    for(const p of pixels)reserved[p]=1;
  }

  // Green grass is almost entirely blue-free. Leaf shadows, canopy outlines and
  // bark have blue/brown values that keep them separate from the bright turf.
  const raw=new Uint8Array(width*height);
  for(let p=0;p<raw.length;p++) {
    if(reserved[p])continue;const q=p*4,r=rgba[q],g=rgba[q+1],b=rgba[q+2];
    if((g>r*1.10&&b>=22&&b<g*.7)||(r<55&&g<79&&b>=7&&b<35))raw[p]=1;
  }
  // Closing rejoins bright leaf highlights within their surrounding dark leaves.
  const rawClean=new Uint8Array(width*height);
  for(const c of components(raw,width,height,60))for(const p of c)rawClean[p]=1;
  let foliage=fillHoles(erode(dilate(rawClean,width,height,2),width,height,2),width,height);
  const cleaned=new Uint8Array(width*height);
  for(const c of components(foliage,width,height,160))for(const p of c)cleaned[p]=1;
  foliage=cleaned;
  // Preserve the small bright leaf tips just outside the connected dark crown.
  // They can be smaller than the seed-component cutoff, but are still foreground
  // pixels. A bounded color-aware fringe avoids leaving chopped tips in turf.
  const nearFoliage=dilate(foliage,width,height,3);
  for(let p=0;p<foliage.length;p++)if(nearFoliage[p]&&!reserved[p]) {
    const q=p*4,r=rgba[q],g=rgba[q+1],b=rgba[q+2];
    if(raw[p]||(g>r*1.28&&g<215&&b>=7&&b<g*.55))foliage[p]=1;
  }
  const specs=spec.trees.map((t,index)=>({index,box:[t[0]*sx,t[1]*sy,t[2]*sx,t[3]*sy],foot:[t[4]*sx,t[5]*sy],pixels:[]}));
  // Roots and trunks are included from narrow measured regions under each crown.
  for(const t of specs) {
    const [x0,y0,x1,y1]=t.box,fx=t.foot[0],fy=t.foot[1],wide=(x1-x0)*.15;
    for(let y=Math.max(0,Math.floor(fy-(y1-y0)*.35));y<=Math.min(height-1,Math.ceil(fy+3*sy));y++) {
      const half=wide*(.45+.55*(y-fy+(y1-y0)*.35)/((y1-y0)*.35));
      for(let x=Math.max(0,Math.floor(fx-half));x<=Math.min(width-1,Math.ceil(fx+half));x++) {
        const p=y*width+x,q=p*4,r=rgba[q],g=rgba[q+1],b=rgba[q+2];
        if(!reserved[p]&&r>=g*.9&&r<160&&g<125&&b>=7&&b<g*.9)foliage[p]=1;
      }
    }
  }
  // Whole source components are partitioned by measured crowns only where two
  // canopies touch. Every chosen pixel belongs to exactly one object scene.
  for(let p=0;p<foliage.length;p++) {
    if(!foliage[p]||reserved[p])continue;const x=p%width,y=(p/width)|0;
    let nearest=null,score=Infinity;
    for(const t of specs) {
      const [x0,y0,x1,y1]=t.box;
      // The measured rectangles describe a crown's main mass. Several approved
      // crowns have leaf tips beyond that mass; own those pixels as well rather
      // than leaving straight rectangular cuts behind when the tree is moved.
      const margin=16*Math.max(sx,sy);
      if(x<x0-margin||x>x1+margin||y<y0-margin||y>y1+margin)continue;
      const cx=(x0+x1)/2,cy=y0+(y1-y0)*.43;
      const d=((x-cx)/((x1-x0)*.55))**2+((y-cy)/((y1-y0)*.60))**2;
      if(d<1.85&&d<score){score=d;nearest=t;}
    }
    if(nearest)nearest.pixels.push(p);
  }
  for(const t of specs) {
    if(t.pixels.length<150)continue;
    const radius=Math.max(5*sx,Math.min(18*sx,(t.box[2]-t.box[0])*.062));
    add('Trees',t.pixels,t.foot,{name:`Tree_${String(t.index+1).padStart(2,'0')}`,circles:[{center:t.foot,radius}]});
  }

  // Remaining isolated bushes/saplings are independently paintable. Very small
  // ground growth stays in the terrain details rather than becoming a collider.
  const remaining=new Uint8Array(width*height);
  for(let p=0;p<remaining.length;p++)if(foliage[p]&&!foregroundMask[p]&&!reserved[p])remaining[p]=1;
  // Every remaining connected foliage pixel receives an owner, even a thin
  // fragment or a large connected forest edge. Ignoring those components would
  // falsely advertise leaf-contaminated terrain as a clean grass donor.
  for(const c of components(remaining,width,height,1)) {
    const bounds=boundsFor(c,width),w=bounds[2]-bounds[0],h=bounds[3]-bounds[1];
    const foot=[(bounds[0]+bounds[2])/2,bounds[3]-2*sy];
    let bark=0,green=0,maxGreen=0;for(const p of c){const y=(p/width)|0,q=p*4,r=rgba[q],g=rgba[q+1],b=rgba[q+2];if(g>r*1.12)green++;maxGreen=Math.max(maxGreen,g);if(y>bounds[3]-h*.28&&r>g*1.15&&r>35&&g<115&&b>9&&b<r*.65)bark++;}
    if(bark>=7&&c.length>=110&&w>=12*sx&&h>=12*sy&&w<=220*sx&&h<=220*sy&&green>=c.length*.48&&maxGreen>=90) add('Trees',c,foot,{name:'SaplingOrShrub',circles:[{center:foot,radius:Math.max(4*sx,Math.min(8*sx,w*.10))}]});
    else add('GroundDetails',c,foot,{name:'LowGrowth',walkable:true});
  }

  return {objects,foregroundMask,classMask,classNames:CLASSES,sourceSize:[width,height],sectionId:key};
}

module.exports={extractWildernessObjects,CLASSES,AREAS};
