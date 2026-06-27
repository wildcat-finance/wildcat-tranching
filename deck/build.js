const pptxgen = require("pptxgenjs");
const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5
pres.author = "Wildcat";
pres.title = "In-House Tranching: Effort Assessment";

// ---------- palette ----------
const INK="16130F", INK2="221C14", AMBER="B4670D", AMBERB="D98412",
      CREAM="FBF8F2", WHITE="FFFFFF", LINE="E4DDD1", LINE2="CFC6B6",
      MUTED="6B6359", INKSOFT="3A352E", GREEN="2F6F4F", RED="9A3412",
      LIGHTBG="FCFAF6";
const F="Arial";
const W=13.33, H=7.5, ML=0.6, CW=W-2*ML;

const sh = () => ({ type:"outer", color:"000000", blur:8, offset:3, angle:90, opacity:0.10 });

function footer(slide, dark){
  const c = dark ? "8A8174" : MUTED;
  slide.addText([
    {text:"Wildcat", options:{bold:true,color:dark?"C9B89A":INKSOFT}},
    {text:"  ·  In-House Tranching Effort Assessment", options:{color:c}},
  ], {x:ML, y:7.05, w:9, h:0.3, fontFace:F, fontSize:8, align:"left", margin:0, charSpacing:0.5});
  slide.addText("CONFIDENTIAL", {x:W-ML-3, y:7.05, w:3, h:0.3, fontFace:F, fontSize:8,
    color:c, align:"right", margin:0, charSpacing:1});
}

function kicker(slide, text, color){
  slide.addText(text, {x:ML, y:0.42, w:CW, h:0.3, fontFace:F, fontSize:10.5, bold:true,
    color:color||AMBER, charSpacing:2, margin:0});
}
function title(slide, text){
  slide.addText(text, {x:ML, y:0.74, w:CW, h:0.62, fontFace:F, fontSize:27, bold:true,
    color:INK, margin:0});
}
function card(slide,x,y,w,h,fill){
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {x,y,w,h, rectRadius:0.07,
    fill:{color:fill||WHITE}, line:{color:LINE,width:1}, shadow:sh()});
}
function circle(slide,x,y,d,txt,fill,tc,fs){
  slide.addShape(pres.shapes.OVAL,{x,y,w:d,h:d,fill:{color:fill},line:{type:"none"}});
  slide.addText(txt,{x,y,w:d,h:d,align:"center",valign:"middle",color:tc||WHITE,bold:true,
    fontFace:F,fontSize:fs||13,margin:0});
}
function badge(slide,x,y,w,txt,fill){
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE,{x,y,w,h:0.32,rectRadius:0.16,fill:{color:fill},line:{type:"none"}});
  slide.addText(txt,{x,y,w,h:0.32,align:"center",valign:"middle",color:WHITE,bold:true,
    fontFace:F,fontSize:8.5,charSpacing:0.7,margin:0});
}

/* ============================ SLIDE 1: TITLE ============================ */
let s = pres.addSlide();
s.background = {color:INK};
kicker(s, "WILDCAT  ·  STRATEGY & ENGINEERING ASSESSMENT", AMBERB);
s.addText([
  {text:"Building Tranching ", options:{color:WHITE}},
  {text:"In-House", options:{color:AMBERB}},
  {text:"\nvs. Partnering", options:{color:WHITE}},
], {x:ML, y:2.15, w:9.6, h:2.0, fontFace:F, fontSize:46, bold:true, lineSpacingMultiple:1.02, margin:0});
s.addText("What it would take Wildcat to ship its own senior / junior tranching layer covering the common ground of Strata, Royco Dawn and Pareto, and whether it should.",
  {x:ML, y:4.5, w:9.4, h:1.1, fontFace:F, fontSize:16, color:"C9BFAE", lineSpacingMultiple:1.18, margin:0});
// stacked-tranche motif (right)
const mx=10.7, mw=2.0;
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:mx,y:2.25,w:mw,h:0.62,rectRadius:0.06,fill:{color:AMBERB},line:{type:"none"}});
s.addText("SENIOR",{x:mx,y:2.25,w:mw,h:0.62,align:"center",valign:"middle",bold:true,color:INK,fontFace:F,fontSize:11,charSpacing:1,margin:0});
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:mx,y:2.99,w:mw,h:0.62,rectRadius:0.06,fill:{color:INK2},line:{color:"4A4031",width:1}});
s.addText("MEZZ",{x:mx,y:2.99,w:mw,h:0.62,align:"center",valign:"middle",bold:true,color:"C9BFAE",fontFace:F,fontSize:11,charSpacing:1,margin:0});
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:mx,y:3.73,w:mw,h:0.62,rectRadius:0.06,fill:{color:INK2},line:{color:"4A4031",width:1}});
s.addText("JUNIOR",{x:mx,y:3.73,w:mw,h:0.62,align:"center",valign:"middle",bold:true,color:"C9BFAE",fontFace:F,fontSize:11,charSpacing:1,margin:0});
s.addText("first-loss",{x:mx,y:4.4,w:mw,h:0.3,align:"center",color:"8A8174",italic:true,fontFace:F,fontSize:9,margin:0});
// bottom meta
s.addShape(pres.shapes.LINE,{x:ML,y:6.7,w:CW,h:0,line:{color:"3A3325",width:1}});
s.addText([
  {text:"27 June 2026", options:{bold:true,color:WHITE}},
  {text:"     Ethereum mainnet", options:{color:"8A8174"}},
], {x:ML, y:6.85, w:8, h:0.35, fontFace:F, fontSize:11, margin:0});
s.addText("CONFIDENTIAL", {x:W-ML-3, y:6.85, w:3, h:0.35, fontFace:F, fontSize:9.5,
  color:"8A8174", align:"right", charSpacing:1.5, margin:0});

/* ============================ SLIDE 2: BOTTOM LINE ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
circle(s, ML, 0.5, 0.34, "★", AMBER, WHITE, 13);
s.addText("Bottom line",{x:ML+0.46,y:0.46,w:10,h:0.45,fontFace:F,fontSize:24,bold:true,color:INK,margin:0,valign:"middle"});
// the number callout
card(s, ML, 1.2, CW, 1.95, CREAM);
s.addText("THE NUMBER",{x:ML+0.35,y:1.42,w:6,h:0.28,fontFace:F,fontSize:10,bold:true,color:AMBER,charSpacing:1.5,margin:0});
s.addText([
  {text:"An in-house MVP covering the common ground", options:{bold:true}},
  {text:" (two share classes over a Wildcat market, a yield waterfall with senior priority + floor and junior residual + risk premium, a junior-first loss waterfall, per-tranche NAV, a coverage ratio, async redemptions through Wildcat’s withdrawal queue, plus a factory + roles) runs about ",options:{}},
  {text:"4–6 engineer-months of build + a ~$80–150k audit, ≈ 3.5–5 months calendar with two strong Solidity engineers.",options:{bold:true,color:AMBER}},
],{x:ML+0.35,y:1.72,w:CW-0.7,h:1.3,fontFace:F,fontSize:14.5,color:INKSOFT,lineSpacingMultiple:1.12,margin:0});
// 4 stats
const stats=[["4–6","ENGINEER-MONTHS BUILD"],["3.5–5","MONTHS CALENDAR · 2 ENGS"],["$80–150k","EXTERNAL AUDIT"],["~1–2k","LINES OF NOVEL CODE"]];
const gw=(CW-3*0.3)/4;
stats.forEach((st,i)=>{
  const x=ML+i*(gw+0.3);
  card(s,x,3.45,gw,1.35,WHITE);
  s.addText(st[0],{x:x+0.1,y:3.62,w:gw-0.2,h:0.7,fontFace:F,fontSize:33,bold:true,color:AMBER,align:"center",valign:"middle",margin:0});
  s.addText(st[1],{x:x+0.12,y:4.32,w:gw-0.24,h:0.4,fontFace:F,fontSize:9,bold:true,color:MUTED,align:"center",charSpacing:0.5,margin:0});
});
// parity note
card(s, ML, 5.05, CW, 1.0, WHITE);
s.addText([
  {text:"Full feature parity ",options:{bold:true,color:INK}},
  {text:"with Strata / Royco (adaptive yield-split curves, depeg handling, isolated liquidity routing, fixed-term recovery, Pendle) adds ",options:{color:INKSOFT}},
  {text:"+3–5 months",options:{bold:true,color:AMBER}},
  {text:", and almost none of it is needed for the Wintermute facility. The novel, security-critical logic is only ~600–2,000 lines in every one of these protocols.",options:{color:INKSOFT}},
],{x:ML+0.35,y:5.2,w:CW-0.7,h:0.75,fontFace:F,fontSize:12.5,lineSpacingMultiple:1.12,valign:"middle",margin:0});
footer(s,false);

/* ============================ SLIDE 3: THREE PROTOCOLS ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"THE BRIEF");
title(s,"The three reference protocols");
const proto=[
  {n:"Strata",repo:"contracts-tranches",d:"CDO-style risk-tranching over any ERC4626. Three accounting engines, cooldown silos, isolated dual-strategy routing.",b:"TRUE TRANCHING · FULL",bc:GREEN},
  {n:"Royco Dawn",repo:"royco-dawn",d:"From-scratch senior/junior engine, NOT the order-matching “Royco Markets.” Dual-NAV, IL recovery, fixed-term state machine, self-liquidation.",b:"TRUE TRANCHING · MOST ADVANCED",bc:GREEN},
  {n:"Pareto",repo:"USP",d:"A synthetic dollar (USP) + first-loss staking (sUSP) that BUYS the senior (AA) tranche of external Idle credit vaults. It only consumes tranching.",b:"ENGINE NOT IN REPO",bc:RED},
];
const c3w=(CW-2*0.35)/3;
proto.forEach((p,i)=>{
  const x=ML+i*(c3w+0.35);
  card(s,x,1.7,c3w,3.7,WHITE);
  s.addText(p.n,{x:x+0.3,y:2.0,w:c3w-0.6,h:0.45,fontFace:F,fontSize:19,bold:true,color:INK,margin:0});
  s.addText(p.repo,{x:x+0.3,y:2.46,w:c3w-0.6,h:0.3,fontFace:"Courier New",fontSize:10.5,color:MUTED,margin:0});
  s.addShape(pres.shapes.LINE,{x:x+0.3,y:2.85,w:c3w-0.6,h:0,line:{color:LINE,width:1}});
  s.addText(p.d,{x:x+0.3,y:3.0,w:c3w-0.6,h:1.7,fontFace:F,fontSize:12.5,color:INKSOFT,lineSpacingMultiple:1.16,margin:0,valign:"top"});
  badge(s,x+0.3,4.9,c3w-0.6,p.b,p.bc);
});
card(s, ML, 5.65, CW, 0.78, CREAM);
s.addText([
  {text:"So “what all three do” really means “what Strata and Royco do natively.” ",options:{bold:true,color:INK}},
  {text:"Pareto’s AA/BB tranche engine lives in Idle’s contracts, not in this repo.",options:{color:INKSOFT}},
],{x:ML+0.35,y:5.74,w:CW-0.7,h:0.6,fontFace:F,fontSize:12,lineSpacingMultiple:1.1,valign:"middle",margin:0});
footer(s,false);

/* ============================ SLIDE 4: ON-CHAIN STACK ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"WHAT’S LIVE ON-CHAIN TODAY");
title(s,"The Wintermute facility, end to end");
const boxes=[
  {t:"USDC",code:"",sub:"base asset",fill:WHITE,tc:INK},
  {t:"Wildcat market",code:"wmtUSDC",sub:"rebasing credit token",fill:WHITE,tc:INK},
  {t:"ERC-4626 wrapper",code:"v-wmtUSDC",sub:"Wildcat’s own · non-rebasing",fill:CREAM,tc:INK},
  {t:"Strata tranches",code:"sr- / jr-wmtUSDC",sub:"senior / junior split",fill:INK,tc:WHITE},
];
const bw=2.72, bgap=0.55, bx0=ML+ (CW-(4*bw+3*bgap))/2, by=2.15, bh=1.5;
boxes.forEach((b,i)=>{
  const x=bx0+i*(bw+bgap);
  s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x,y:by,w:bw,h:bh,rectRadius:0.08,
    fill:{color:b.fill},line:{color:b.fill===INK?INK:LINE2,width:1},shadow:sh()});
  s.addText(b.t,{x:x+0.1,y:by+0.22,w:bw-0.2,h:0.4,align:"center",bold:true,fontFace:F,fontSize:14,color:b.tc,margin:0});
  if(b.code) s.addText(b.code,{x:x+0.1,y:by+0.63,w:bw-0.2,h:0.32,align:"center",fontFace:"Courier New",fontSize:11.5,bold:true,color:b.fill===INK?AMBERB:AMBER,margin:0});
  s.addText(b.sub,{x:x+0.1,y:by+(b.code?0.98:0.8),w:bw-0.2,h:0.4,align:"center",fontFace:F,fontSize:9.5,italic:true,color:b.fill===INK?"C9BFAE":MUTED,margin:0});
  if(i<3){
    const ax=x+bw+0.06;
    s.addShape(pres.shapes.LINE,{x:ax,y:by+bh/2,w:bgap-0.12,h:0,
      line:{color:AMBER,width:2.25,endArrowType:"triangle"}});
  }
});
// correction callout
card(s, ML, 4.15, CW, 1.5, WHITE);
circle(s, ML+0.3, 4.4, 0.34, "!", AMBER, WHITE, 14);
s.addText("On-chain check: confirm the target market",{x:ML+0.78,y:4.4,w:CW-1.1,h:0.32,fontFace:F,fontSize:13,bold:true,color:INK,margin:0,valign:"middle"});
s.addText([
  {text:"v-wmtUSDC (",options:{}},{text:"0xf654…",options:{fontFace:"Courier New",bold:true,color:AMBER}},
  {text:") is Wildcat’s own 4626 wrapper, not a Strata contract. It wraps ",options:{}},
  {text:"0xC949…",options:{fontFace:"Courier New",bold:true,color:AMBER}},
  {text:", “Wintermute Trading USD Coin” (~$69.65M, 8.5% APR), a ",options:{}},
  {text:"different market",options:{bold:true}},
  {text:" from the ",options:{}},{text:"0x50ebdf…",options:{fontFace:"Courier New",bold:true,color:AMBER}},
  {text:" (~$2.23M). Strata’s split is lender-side only; the borrower still sees a single unitranche facility.",options:{}},
],{x:ML+0.78,y:4.78,w:CW-1.15,h:0.8,fontFace:F,fontSize:11.5,color:INKSOFT,lineSpacingMultiple:1.14,margin:0});
s.addText("Tranching attaches as a separate vault on top of an unchanged market; it is not a protocol fork.",
  {x:ML,y:5.95,w:CW,h:0.4,fontFace:F,fontSize:12,italic:true,color:MUTED,align:"center",margin:0});
footer(s,false);

/* ============================ SLIDE 5: COMMON GROUND ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"THE INTERSECTION YOU’D REBUILD");
title(s,"The common ground: eight primitives");
const prim=[
  ["Two share classes","Senior + junior over one ERC4626 underlying."],
  ["Yield waterfall","Senior priority + floor; junior residual + risk premium."],
  ["Loss waterfall","Junior first-loss; cascades junior → reserve → senior."],
  ["Per-tranche NAV","Marked off the underlying, re-synced each interaction."],
  ["Coverage ratio","Caps senior leverage; gates deposits/exits near the floor."],
  ["Async redemption","Cooldown silos or a request → execute queue."],
  ["Governance","Sets senior rate, pauses, manages reserve & shortfall."],
  ["Factory","Deploys a tranche set per underlying."],
];
const colW=(CW-0.5)/2, rowH=0.92, gy=1.7;
prim.forEach((p,i)=>{
  const col=i%2, row=Math.floor(i/2);
  const x=ML+col*(colW+0.5), y=gy+row*rowH;
  circle(s,x,y+0.04,0.4,String(i+1),AMBER,WHITE,14);
  s.addText(p[0],{x:x+0.56,y:y-0.02,w:colW-0.56,h:0.3,fontFace:F,fontSize:13.5,bold:true,color:INK,margin:0});
  s.addText(p[1],{x:x+0.56,y:y+0.28,w:colW-0.56,h:0.5,fontFace:F,fontSize:11.5,color:INKSOFT,lineSpacingMultiple:1.05,margin:0});
});
card(s, ML, 5.6, CW, 0.82, CREAM);
s.addText([
  {text:"Beyond this line is differentiation, not common ground: ",options:{bold:true,color:INK}},
  {text:"Royco’s fixed-term recovery, IL tracking, self-liquidation; Strata’s adaptive curve, depeg oracle, isolated liquidity routing.",options:{color:INKSOFT}},
],{x:ML+0.35,y:5.71,w:CW-0.7,h:0.6,fontFace:F,fontSize:12,lineSpacingMultiple:1.1,valign:"middle",margin:0});
footer(s,false);

/* ============================ SLIDE 6: WILDCAT HAS / SEAM ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"STARTING POSITION");
title(s,"You’re not starting from zero");
const lw=CW*0.56;
card(s, ML, 1.7, lw, 4.7, WHITE);
s.addText("REUSE DIRECTLY",{x:ML+0.35,y:1.95,w:lw-0.7,h:0.3,fontFace:F,fontSize:11,bold:true,color:AMBER,charSpacing:1.5,margin:0});
const reuse=[
  ["Wildcat4626Wrapper","the deployed v-wmtUSDC; solves rebasing→non-rebasing + sanctions. ~80% of one tranche’s plumbing."],
  ["scaleFactor() accrual oracle","interest accrues monotonically, easier than diffing a noisy 4626 share price."],
  ["Math + infra","ray/bip math, SafeCast, FIFOQueue, Solady ERC20/4626/permit bases."],
  ["Factory pattern","permissionless, arch-gated, one-per-market; copy for a TrancheVaultFactory."],
  ["Sanctions sentinel","existing pattern to re-enforce at the vault layer."],
  ["Test + audit rigor","invariant tests, fuzzing, a16z 4626 suite, external audits."],
];
let yy=2.35;
reuse.forEach(r=>{
  circle(s, ML+0.35, yy+0.03, 0.16, "", AMBER, WHITE, 8);
  s.addText([
    {text:r[0]+": ",options:{bold:true,color:INK}},
    {text:r[1],options:{color:INKSOFT}},
  ],{x:ML+0.62,y:yy-0.06,w:lw-0.95,h:0.62,fontFace:F,fontSize:11.5,lineSpacingMultiple:1.04,margin:0});
  yy+=0.68;
});
// seam callout (right, dark)
const rx=ML+lw+0.4, rw=CW-lw-0.4;
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:rx,y:1.7,w:rw,h:4.7,rectRadius:0.07,fill:{color:INK},line:{type:"none"},shadow:sh()});
s.addText("THE ARCHITECTURAL SEAM",{x:rx+0.32,y:1.98,w:rw-0.64,h:0.3,fontFace:F,fontSize:11,bold:true,color:AMBERB,charSpacing:1.2,margin:0});
s.addText("Tranching can’t live in hooks.",{x:rx+0.32,y:2.4,w:rw-0.64,h:0.7,fontFace:F,fontSize:18,bold:true,color:WHITE,lineSpacingMultiple:1.05,margin:0});
s.addText([
  {text:"Hooks are reactive: they can revert and tweak APR/reserve, but cannot route funds or hold dual-class accounting.",options:{breakLine:true,paraSpaceAfter:12}},
  {text:"The tranche logic must be a separate vault that holds the market token and issues senior / junior shares. Hooks can only assist, e.g. gate who may deposit.",options:{}},
],{x:rx+0.32,y:3.25,w:rw-0.64,h:2.8,fontFace:F,fontSize:12.5,color:"D8CEBE",lineSpacingMultiple:1.18,valign:"top",margin:0});
footer(s,false);

/* ============================ SLIDE 7: HARD PARTS ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"WHERE THE MONTHS ACTUALLY GO");
title(s,"Three Wildcat-specific hard parts");
const hard=[
  {t:"Credit-loss ≠ mark-to-market",tag:"KEY UNKNOWN",tc:AMBER,
   d:"The others detect loss as a falling 4626 price. Wildcat’s loss is lumpy: delinquency (principal intact) vs default/closure shortfall. You must define the impairment trigger and recovery socialization before any junior write-down can be coded.",
   note:"Design + legal, not code."},
  {t:"Redemptions through the queue",tag:"BIGGEST NET-NEW",tc:INKSOFT,
   d:"Wildcat exits are batched, expiry-dated, FIFO, pro-rata and time-delayed. The vault must queue → wait → execute, then allocate the partial, delayed proceeds senior-first per the waterfall.",
   note:"No template exists in any of the three."},
  {t:"Per-user KYC at the vault",tag:"WILDCAT-SPECIFIC",tc:INKSOFT,
   d:"Pooling lenders hides individuals from the market, which only sees the vault. Credentials and sanctions must be re-enforced inside the vault on every entry and share transfer.",
   note:"The 4626 wrapper shows the pattern."},
];
const hw=(CW-2*0.35)/3;
hard.forEach((p,i)=>{
  const x=ML+i*(hw+0.35);
  card(s,x,1.75,hw,4.45,WHITE);
  circle(s,x+0.3,2.05,0.42,String(i+1),i===0?AMBER:INK,WHITE,15);
  badge(s,x+0.85,2.1,hw-1.15,p.tag,p.tc);
  s.addText(p.t,{x:x+0.3,y:2.7,w:hw-0.6,h:0.75,fontFace:F,fontSize:15.5,bold:true,color:INK,lineSpacingMultiple:1.02,margin:0});
  s.addText(p.d,{x:x+0.3,y:3.5,w:hw-0.6,h:1.9,fontFace:F,fontSize:11.5,color:INKSOFT,lineSpacingMultiple:1.16,margin:0,valign:"top"});
  s.addShape(pres.shapes.LINE,{x:x+0.3,y:5.55,w:hw-0.6,h:0,line:{color:LINE,width:1}});
  s.addText(p.note,{x:x+0.3,y:5.62,w:hw-0.6,h:0.5,fontFace:F,fontSize:11,bold:true,italic:true,color:AMBER,lineSpacingMultiple:1.05,margin:0});
});
footer(s,false);

/* ============================ SLIDE 8: EFFORT TABLE ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"THE NUMBER, PHASED");
title(s,"Effort estimate");
const hdr = (t)=>({text:t,options:{bold:true,color:WHITE,fill:{color:INK},fontSize:11,align:"left",valign:"middle",margin:[4,6,4,6]}});
const cell=(t,o={})=>({text:t,options:Object.assign({fontSize:11,color:INKSOFT,valign:"middle",margin:[4,6,4,6],fontFace:F},o)});
const rows=[
  [hdr("Phase"),hdr("Scope"),hdr("New Solidity"),hdr("Calendar")],
  [cell("0. Design & risk spec",{bold:true,color:INK}),cell("Loss model, redemption allocation, coupon-vs-delinquency, param bounds. The real work."),cell("spec, not code"),cell("3–5 wks")],
  [cell("1. MVP core",{bold:true,color:INK}),cell("2 tranche tokens; both waterfalls; coverage gating; NAV off scaleFactor; redemption orchestration; factory; roles; pause."),cell("~3.5–5k LOC"),cell("6–10 wks")],
  [cell("2. Hardening",{bold:true,color:INK}),cell("Invariant + fuzz to your bar, a16z 4626 suite, default / partial-fill edges, vault-layer KYC."),cell("folded in"),cell("4–6 wks")],
  [cell("3. Audit + fixes",{bold:true,color:INK}),cell("External audit + remediation."),cell("n/a"),cell("4–8 wks (+$80–150k)")],
  [cell("MVP TOTAL",{bold:true,color:INK,fill:{color:"F4E4C9"}}),cell("Common ground, audited",{bold:true,color:INK,fill:{color:"F4E4C9"}}),cell("~4–6 eng-months",{bold:true,color:AMBER,fill:{color:"F4E4C9"}}),cell("~3.5–5 months",{bold:true,color:AMBER,fill:{color:"F4E4C9"}})],
  [cell("4. Advanced (optional)",{bold:true,color:INK}),cell("Adaptive curve, depeg oracle, isolated routing, fixed-term recovery, Pendle."),cell("+3–6k LOC"),cell("+3–5 months")],
];
s.addTable(rows,{x:ML,y:1.7,w:CW,colW:[2.55,6.43,1.7,1.65],
  border:{type:"solid",pt:0.5,color:LINE2}, rowH:[0.4,0.62,0.78,0.62,0.5,0.5,0.62],
  fill:{color:WHITE}, autoPage:false, valign:"middle"});
card(s, ML, 6.15, CW, 0.72, CREAM);
s.addText([
  {text:"Why not faster, given the IP is ~1–2k LOC?  ",options:{bold:true,color:INK}},
  {text:"Calendar is dominated by the loss-model design, the template-less redemption integration, and audit, not line count.",options:{color:INKSOFT}},
],{x:ML+0.35,y:6.24,w:CW-0.7,h:0.55,fontFace:F,fontSize:11.5,lineSpacingMultiple:1.1,valign:"middle",margin:0});
footer(s,false);

/* ============================ SLIDE 9: BUILD VS PARTNER ============================ */
s = pres.addSlide(); s.background={color:LIGHTBG};
kicker(s,"THE DECISION");
title(s,"Build vs. partner");
const opts=[
  {h:"Partner (Strata)",hc:GREEN,d:"Tranches live in weeks, ~zero Wildcat engineering. Strata brings NAV accounting, waterfalls, yield distribution and enforced mint/redeem; you bring the market + joint UI.",cost:"Cost: revenue share · external trust surface · less control over UX & roadmap."},
  {h:"Build in-house",hc:AMBER,d:"Full control, no revenue share, native UX, and a factory that makes it reusable across every Wildcat market.",cost:"Cost: the quarter-plus opposite · owning audit + maintenance · owning the credit-loss-model risk."},
  {h:"Pragmatic middle",hc:INK,d:"Partner now to ship Wintermute and learn real demand, while running the cheap Phase 0 in parallel.",cost:"Phase 0 de-risks the whole build; decide on Phase 1 once the loss model & redemption design are settled."},
];
const ow=(CW-2*0.35)/3;
opts.forEach((o,i)=>{
  const x=ML+i*(ow+0.35);
  card(s,x,1.7,ow,3.5,WHITE);
  s.addText(o.h,{x:x+0.3,y:2.0,w:ow-0.6,h:0.4,fontFace:F,fontSize:16,bold:true,color:o.hc,margin:0});
  s.addShape(pres.shapes.LINE,{x:x+0.3,y:2.5,w:ow-0.6,h:0,line:{color:LINE,width:1}});
  s.addText(o.d,{x:x+0.3,y:2.62,w:ow-0.6,h:1.7,fontFace:F,fontSize:12,color:INKSOFT,lineSpacingMultiple:1.16,margin:0,valign:"top"});
  s.addText(o.cost,{x:x+0.3,y:4.35,w:ow-0.6,h:0.75,fontFace:F,fontSize:10.5,italic:true,color:MUTED,lineSpacingMultiple:1.12,margin:0});
});
// recommendation strip
s.addShape(pres.shapes.ROUNDED_RECTANGLE,{x:ML,y:5.45,w:CW,h:1.0,rectRadius:0.07,fill:{color:INK},line:{type:"none"},shadow:sh()});
s.addText("RECOMMENDATION",{x:ML+0.4,y:5.62,w:3,h:0.3,fontFace:F,fontSize:10,bold:true,color:AMBERB,charSpacing:1.5,margin:0});
s.addText("Take the Strata facility now; fund Phase 0 in parallel. It de-risks the entire build for a few weeks of one engineer’s time.",
  {x:ML+0.4,y:5.9,w:CW-0.8,h:0.45,fontFace:F,fontSize:14,bold:true,color:WHITE,lineSpacingMultiple:1.05,margin:0,valign:"middle"});
footer(s,false);

/* ============================ SLIDE 10: CLOSING ============================ */
s = pres.addSlide(); s.background={color:INK};
kicker(s,"THE CHEAPEST NEXT STEP", AMBERB);
s.addText([
  {text:"Start with ",options:{color:WHITE}},
  {text:"Phase 0.",options:{color:AMBERB}},
],{x:ML,y:2.2,w:11,h:1.0,fontFace:F,fontSize:44,bold:true,margin:0});
s.addText("A 3–5 week design spec (impairment trigger, recovery socialization, and the redemption-allocation algorithm) settles the only real unknowns and lets Wildcat commit to build-or-buy with eyes open.",
  {x:ML,y:3.5,w:10.6,h:1.6,fontFace:F,fontSize:18,color:"D8CEBE",lineSpacingMultiple:1.3,margin:0});
s.addShape(pres.shapes.LINE,{x:ML,y:6.7,w:CW,h:0,line:{color:"3A3325",width:1}});
s.addText([
  {text:"Wildcat",options:{bold:true,color:"C9B89A"}},
  {text:"  ·  In-House Tranching Effort Assessment  ·  27 June 2026",options:{color:"8A8174"}},
],{x:ML,y:6.85,w:10,h:0.35,fontFace:F,fontSize:11,margin:0});
s.addText("CONFIDENTIAL",{x:W-ML-3,y:6.85,w:3,h:0.35,fontFace:F,fontSize:9.5,color:"8A8174",align:"right",charSpacing:1.5,margin:0});

pres.writeFile({fileName:"Wildcat-Tranching-Assessment-Deck.pptx"}).then(f=>console.log("WROTE",f));
