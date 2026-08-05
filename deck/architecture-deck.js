const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.author = "Wildcat";
pres.title = "In-House Tranching: Architecture & Design Overview";

const INK="16130F", INK2="221C14", AMBER="B4670D", AMBERB="D98412",
      CREAM="FBF8F2", WHITE="FFFFFF", LINE="E4DDD1", LINE2="CFC6B6",
      MUTED="6B6359", INKSOFT="3A352E", GREEN="2F6F4F", LIGHTBG="FCFAF6";
const F="Arial";
const W=13.33, H=7.5, ML=0.6, CW=W-2*ML;
const sh = () => ({ type:"outer", color:"000000", blur:8, offset:3, angle:90, opacity:0.10 });

function footer(s){ s.addText([{text:"Wildcat",options:{bold:true,color:INKSOFT}},{text:"  ·  In-House Tranching: Architecture & Design Overview",options:{color:MUTED}}],{x:ML,y:7.05,w:10,h:0.3,fontFace:F,fontSize:8,margin:0,charSpacing:0.5});
  s.addText("CONFIDENTIAL",{x:W-ML-3,y:7.05,w:3,h:0.3,fontFace:F,fontSize:8,color:MUTED,align:"right",margin:0,charSpacing:1}); }
function kicker(s,t,c){ s.addText(t,{x:ML,y:0.42,w:CW,h:0.3,fontFace:F,fontSize:10.5,bold:true,color:c||AMBER,charSpacing:2,margin:0}); }
function title(s,t){ s.addText(t,{x:ML,y:0.74,w:CW,h:0.62,fontFace:F,fontSize:26,bold:true,color:INK,margin:0}); }
function card(s,x,y,w,h,fill){ s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x,y,w,h,rectRadius:0.07,fill:{color:fill||WHITE},line:{color:LINE,width:1},shadow:sh()}); }
function circle(s,x,y,d,txt,fill,tc,fs){ s.addShape(pres.shapes.OVAL,{x,y,w:d,h:d,fill:{color:fill},line:{type:"none"}});
  s.addText(txt,{x,y,w:d,h:d,align:"center",valign:"middle",color:tc||WHITE,bold:true,fontFace:F,fontSize:fs||13,margin:0}); }

/* ===== S1 TITLE (dark) ===== */
let s = pres.addSlide(); s.background={color:INK};
kicker(s,"WILDCAT  ·  IN-HOUSE TRANCHING",AMBERB);
s.addText([{text:"Architecture &\n",options:{color:WHITE}},{text:"Design Overview",options:{color:AMBERB}}],
  {x:ML,y:2.2,w:9.6,h:1.9,fontFace:F,fontSize:42,bold:true,lineSpacingMultiple:1.03,margin:0});
s.addText("A senior / junior credit-tranche vault layered on the Wildcat v-abcUSDC market wrapper: its contracts, how it attaches, the design decisions, and the properties it guarantees.",
  {x:ML,y:4.55,w:9.5,h:1.1,fontFace:F,fontSize:15.5,color:"C9BFAE",lineSpacingMultiple:1.2,margin:0});
const mx=10.8, mw=1.95;
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:mx,y:2.45,w:mw,h:0.62,rectRadius:0.06,fill:{color:AMBERB},line:{type:"none"}});
s.addText("SENIOR",{x:mx,y:2.45,w:mw,h:0.62,align:"center",valign:"middle",bold:true,color:INK,fontFace:F,fontSize:11,charSpacing:1,margin:0});
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:mx,y:3.19,w:mw,h:0.62,rectRadius:0.06,fill:{color:INK2},line:{color:"4A4031",width:1}});
s.addText("JUNIOR",{x:mx,y:3.19,w:mw,h:0.62,align:"center",valign:"middle",bold:true,color:"C9BFAE",fontFace:F,fontSize:11,charSpacing:1,margin:0});
s.addText("first-loss",{x:mx,y:3.86,w:mw,h:0.3,align:"center",color:"8A8174",italic:true,fontFace:F,fontSize:9,margin:0});
s.addShape(pres.shapes.LINE,{x:ML,y:6.7,w:CW,h:0,line:{color:"3A3325",width:1}});
s.addText([{text:"Ethereum mainnet",options:{bold:true,color:WHITE}},{text:"     Full rationale in the Design & Risk Specification",options:{color:"8A8174"}}],{x:ML,y:6.85,w:10,h:0.35,fontFace:F,fontSize:11,margin:0});
s.addText("CONFIDENTIAL",{x:W-ML-3,y:6.85,w:3,h:0.35,fontFace:F,fontSize:9.5,color:"8A8174",align:"right",charSpacing:1.5,margin:0});

/* ===== S2 FACTS ===== */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"AT A GLANCE"); title(s,"The structure");
const st=[["Senior + Junior","CAPITAL STACK",INK],["Junior ≥ 20%","FIRST-LOSS",AMBER],["≤ 4×","SENIOR LEVERAGE",INK],["grace + 90d","DEFAULT (ToU §6.2)",INK],["realised-only","VALUATION",INK]];
const gw=(CW-4*0.28)/5;
st.forEach((m,i)=>{ const x=ML+i*(gw+0.28); card(s,x,1.95,gw,1.5,WHITE);
  s.addText(m[0],{x:x+0.08,y:2.18,w:gw-0.16,h:0.7,fontFace:F,fontSize:15,bold:true,color:m[2],align:"center",valign:"middle",margin:0});
  s.addText(m[1],{x:x+0.08,y:2.95,w:gw-0.16,h:0.35,fontFace:F,fontSize:8,bold:true,color:MUTED,align:"center",charSpacing:0.5,margin:0}); });
card(s,ML,3.9,CW,2.4,CREAM);
s.addText("The system in one line",{x:ML+0.35,y:4.1,w:CW-0.7,h:0.3,fontFace:F,fontSize:10,bold:true,color:AMBER,charSpacing:1,margin:0});
s.addText([
  {text:"One Wildcat facility, split on the lender side into a senior priority tranche and a junior first-loss tranche. ",options:{bold:true,color:INK}},
  {text:"Interest pays the senior target first and the residual to junior; losses hit junior to zero before senior is touched. Valuation is realised-only and oracle-free, redemption is asynchronous and senior-first, and default mirrors the Wildcat Terms of Use on-chain. The borrower sees a single unitranche facility throughout.",options:{color:INKSOFT}},
],{x:ML+0.35,y:4.45,w:CW-0.7,h:1.7,fontFace:F,fontSize:13.5,lineSpacingMultiple:1.25,valign:"top",margin:0});
footer(s);

/* ===== S3 CONTRACTS ===== */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"COMPONENTS"); title(s,"Contracts");
const hdr=t=>({text:t,options:{bold:true,color:WHITE,fill:{color:INK},fontSize:11,valign:"middle",margin:[4,6,4,6]}});
const cl=(t,o={})=>({text:t,options:Object.assign({fontSize:11,color:INKSOFT,valign:"middle",margin:[4,6,4,6],fontFace:F},o)});
const mono=(t)=>({text:t,options:{fontSize:10.5,color:INK,fontFace:"Courier New",valign:"middle",margin:[4,6,4,6]}});
const rows=[
  [hdr("Contract"),hdr("Role")],
  [mono("WaterfallMath"),cl("Pure tranche math: senior accrual, value/loss split, subordination, ToU default trigger.")],
  [mono("TrancheController"),cl("Immutable orchestrator: deposits, async redemption queue, default/wind-down, subordination gating, per-user sanctions + escrow. Reentrancy-guarded; safe transfers.")],
  [mono("senior / junior"),cl("sr-abcUSDC / jr-abcUSDC: Solady ERC20 + EIP-2612 permit with an ERC-4626 value-view surface. Senior open to KYC'd lenders; junior whitelisted.")],
  [mono("TrancheFactory"),cl("Registered at the WildcatArchController; one tranche set per registered market, gated on isRegisteredMarket.")],
  [mono("IExternal"),cl("Interfaces to the Wildcat 4626 wrapper, market (state + withdrawal queue), sentinel, and arch controller.")],
];
s.addTable(rows,{x:ML,y:1.8,w:CW,colW:[2.9,9.13],border:{type:"solid",pt:0.5,color:LINE2},
  rowH:[0.36,0.5,0.82,0.72,0.6,0.6],fill:{color:WHITE},valign:"middle",autoPage:false});
footer(s);

/* ===== S4 HOW IT ATTACHES ===== */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"HOW IT ATTACHES"); title(s,"A vault on top of an unchanged market");
const boxes=[
  {t:"USDC",code:"",fill:WHITE},
  {t:"Wildcat market",code:"abcUSDC",fill:WHITE},
  {t:"ERC-4626 wrapper",code:"v-abcUSDC",fill:CREAM},
  {t:"TrancheController",code:"holds + waterfall",fill:INK},
];
const bw=2.62,bgap=0.5,bx0=ML+(CW-(4*bw+3*bgap))/2,by=2.1,bh=1.25;
boxes.forEach((b,i)=>{ const x=bx0+i*(bw+bgap);
  s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x,y:by,w:bw,h:bh,rectRadius:0.08,fill:{color:b.fill},line:{color:b.fill===INK?INK:LINE2,width:1},shadow:sh()});
  s.addText(b.t,{x:x+0.1,y:by+0.26,w:bw-0.2,h:0.4,align:"center",bold:true,fontFace:F,fontSize:13.5,color:b.fill===INK?WHITE:INK,margin:0});
  if(b.code) s.addText(b.code,{x:x+0.1,y:by+0.66,w:bw-0.2,h:0.32,align:"center",fontFace:"Courier New",fontSize:10.5,bold:true,color:b.fill===INK?AMBERB:AMBER,margin:0});
  if(i<3) s.addShape(pres.shapes.LINE,{x:x+bw+0.04,y:by+bh/2,w:bgap-0.08,h:0,line:{color:AMBER,width:2.25,endArrowType:"triangle"}}); });
const cxC=bx0+3*(bw+bgap);
s.addShape(pres.shapes.LINE,{x:cxC+bw/2,y:by+bh,w:0,h:0.4,line:{color:AMBER,width:2,endArrowType:"triangle"}});
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:cxC-0.1,y:by+bh+0.4,w:bw/2-0.05,h:0.55,rectRadius:0.06,fill:{color:AMBERB},line:{type:"none"}});
s.addText("sr-abcUSDC",{x:cxC-0.1,y:by+bh+0.4,w:bw/2-0.05,h:0.55,align:"center",valign:"middle",bold:true,color:INK,fontFace:F,fontSize:10,margin:0});
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:cxC+bw/2,y:by+bh+0.4,w:bw/2-0.05,h:0.55,rectRadius:0.06,fill:{color:INK2},line:{color:"4A4031",width:1}});
s.addText("jr-abcUSDC",{x:cxC+bw/2,y:by+bh+0.4,w:bw/2-0.05,h:0.55,align:"center",valign:"middle",bold:true,color:"E8DDC9",fontFace:F,fontSize:10,margin:0});
card(s,ML,4.95,CW,1.25,WHITE);
s.addText([{text:"Deployment:  ",options:{bold:true,color:INK}},
  {text:"the ",options:{color:INKSOFT}},{text:"TrancheFactory",options:{fontFace:"Courier New",color:AMBER}},
  {text:" is registered at the ",options:{color:INKSOFT}},{text:"WildcatArchController",options:{fontFace:"Courier New",color:AMBER}},
  {text:" (protocol level) and deploys one senior/junior set per registered market, gated on ",options:{color:INKSOFT}},
  {text:"isRegisteredMarket",options:{fontFace:"Courier New",color:AMBER}},
  {text:". Tranching is a lender-side vault on top of an unchanged market.",options:{color:INKSOFT}}],
  {x:ML+0.35,y:5.12,w:CW-0.7,h:0.95,fontFace:F,fontSize:12,lineSpacingMultiple:1.18,valign:"middle",margin:0});
footer(s);

/* ===== S5 THE MODEL ===== */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"DESIGN"); title(s,"The model");
const colW=(CW-0.4)/2;
card(s,ML,1.85,colW,4.5,WHITE);
s.addText("ECONOMICS & RISK",{x:ML+0.32,y:2.1,w:colW-0.64,h:0.3,fontFace:F,fontSize:11,bold:true,color:AMBER,charSpacing:1,margin:0});
const econ=[["Senior","priority claim at a rate derived from the facility APR (a governance-set share of it, capped at the APR); not a guarantee."],["Junior","leveraged first-loss residual: earns the excess spread, absorbs losses to zero before senior."],["Subordination","fixed floor (junior ≥ 20% of TVL, senior ≤ 4×) gating senior deposits & junior exits."],["Valuation","realised-only, oracle-free; NAV frozen at a high-watermark while delinquent."]];
let yy=2.5; econ.forEach(t=>{ circle(s,ML+0.32,yy+0.02,0.15,"",AMBER,WHITE,8);
  s.addText([{text:t[0]+": ",options:{bold:true,color:INK}},{text:t[1],options:{color:INKSOFT}}],{x:ML+0.58,y:yy-0.06,w:colW-0.9,h:0.8,fontFace:F,fontSize:11.5,lineSpacingMultiple:1.08,margin:0}); yy+=0.88; });
const rx=ML+colW+0.4; card(s,rx,1.85,colW,4.5,WHITE);
s.addText("MECHANICS & CONTROLS",{x:rx+0.32,y:2.1,w:colW-0.64,h:0.3,fontFace:F,fontSize:11,bold:true,color:AMBER,charSpacing:1,margin:0});
const mech=[["Redemption","asynchronous, mirroring the market's batched queue; partial proceeds senior-first."],["Default","ToU §6.2 mirror (grace + 90d), per-market configurable + Loan-Agreement override; senior-first wind-down."],["Governance","immutable logic + bounded, timelocked params; pause halts deposits only, never senior exits."],["Compliance","per-user sentinel (sanctioned redemptions → escrow); junior restricted to qualified providers."]];
yy=2.5; mech.forEach(t=>{ circle(s,rx+0.32,yy+0.02,0.15,"",INK,WHITE,8);
  s.addText([{text:t[0]+": ",options:{bold:true,color:INK}},{text:t[1],options:{color:INKSOFT}}],{x:rx+0.58,y:yy-0.06,w:colW-0.9,h:0.8,fontFace:F,fontSize:11.5,lineSpacingMultiple:1.08,margin:0}); yy+=0.88; });
footer(s);

/* ===== S6 PROPERTIES & VERIFICATION ===== */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"GUARANTEES"); title(s,"Properties & verification");
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:ML,y:1.9,w:CW,h:1.35,rectRadius:0.07,fill:{color:CREAM},line:{color:LINE2,width:1}});
s.addText("INVARIANTS",{x:ML+0.35,y:2.08,w:6,h:0.3,fontFace:F,fontSize:10,bold:true,color:AMBER,charSpacing:1.2,margin:0});
s.addText([
  {text:"seniorValue + juniorValue == realisedValue",options:{fontFace:"Courier New",bold:true,color:INK}},
  {text:"  at all times  ·  junior floors at zero before senior is impaired (first-loss)  ·  senior is paid before junior on every settlement (priority).",options:{color:INKSOFT}},
],{x:ML+0.35,y:2.4,w:CW-0.7,h:0.7,fontFace:F,fontSize:12.5,lineSpacingMultiple:1.2,valign:"top",margin:0});
const props=[
  "Built on Solady's audited ERC20, ReentrancyGuard and SafeTransferLib; share conversions round in favour of the pool.",
  "Covered by a Foundry suite: unit / behaviour, property fuzz, and stateful-invariant tests.",
  "Mainnet-fork tests exercise deposit, valuation and a full redemption round-trip against a live production facility and its withdrawal queue.",
];
yy=3.55; props.forEach(t=>{ circle(s,ML+0.05,yy+0.02,0.16,"",GREEN,WHITE,8);
  s.addText(t,{x:ML+0.33,y:yy-0.05,w:CW-0.4,h:0.6,fontFace:F,fontSize:12.5,color:INKSOFT,lineSpacingMultiple:1.12,margin:0}); yy+=0.72; });
card(s,ML,5.85,CW,0.6,WHITE);
s.addText("Not yet audited; independent review focuses on credit-loss / redemption edge cases, the redemption-array gas/DoS profile at scale, and ERC-4626 conformance of the view surface.",
  {x:ML+0.35,y:5.95,w:CW-0.7,h:0.4,fontFace:F,fontSize:10.5,italic:true,color:MUTED,valign:"middle",margin:0});
footer(s);

/* ===== S7 CLOSING (dark) ===== */
s = pres.addSlide(); s.background={color:INK};
kicker(s,"SUMMARY",AMBERB);
s.addText([{text:"Senior & junior, ",options:{color:WHITE}},{text:"on-chain.",options:{color:AMBERB}}],
  {x:ML,y:2.4,w:11.5,h:1.5,fontFace:F,fontSize:42,bold:true,margin:0});
s.addText("A conservative, oracle-free, first-loss credit-tranche vault over the Wildcat v-abcUSDC facility: senior priority with a 20% junior cushion, realised-only valuation, async senior-first redemption, and an on-chain mirror of the facility's own default terms.",
  {x:ML,y:3.8,w:11,h:1.7,fontFace:F,fontSize:17,color:"D8CEBE",lineSpacingMultiple:1.3,margin:0});
s.addShape(pres.shapes.LINE,{x:ML,y:6.7,w:CW,h:0,line:{color:"3A3325",width:1}});
s.addText([{text:"Wildcat",options:{bold:true,color:"C9B89A"}},{text:"  ·  In-House Tranching: Architecture & Design Overview",options:{color:"8A8174"}}],{x:ML,y:6.85,w:11,h:0.35,fontFace:F,fontSize:11,margin:0});
s.addText("CONFIDENTIAL",{x:W-ML-3,y:6.85,w:3,h:0.35,fontFace:F,fontSize:9.5,color:"8A8174",align:"right",charSpacing:1.5,margin:0});

pres.writeFile({fileName:"Wildcat-Tranching-Architecture-Deck.pptx"}).then(f=>console.log("WROTE",f));
