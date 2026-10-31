// PROPOSAL ONLY — NOT IMPLEMENTED. Contrast surfaces rendered without text.
async(page)=>{
 const root='/Users/ghassenbrg/git/miraya/Creative Design/2026-10-29-beam-redesign';
 await page.goto('http://127.0.0.1:8841/?view=tv&state=ready');
 await page.setViewportSize({width:2048,height:1350});
 await page.addStyleTag({content:'.preview-capture.tv-capture,.tv-wrap{width:1920px;max-width:none}'});
 const states=['ready','pairing','approval','offline','lost','expired','details','picture','controls','paused'];const report={status:'PROPOSAL ONLY — NOT IMPLEMENTED',states:[]};
 for(const state of states){
  await page.evaluate(state=>window.beamReview.set('tv',state,{modal:null,tvReturn:['picture'].includes(state)?'controls':'ready'}),state);
  await page.locator('.tv-frame img').evaluateAll(imgs=>Promise.all(imgs.map(i=>i.decode().catch(()=>{}))));
  const geometry=await page.evaluate(()=>{
   const frame=document.querySelector('.tv-frame'),b=frame.getBoundingClientRect(),walker=document.createTreeWalker(frame,NodeFilter.SHOW_TEXT),text=[];let node;
   while(node=walker.nextNode()){if(!node.textContent.trim())continue;const el=node.parentElement,c=getComputedStyle(el);if(c.display==='none'||c.visibility==='hidden')continue;const range=document.createRange();range.selectNodeContents(node);const rects=[...range.getClientRects()].filter(r=>r.width>0&&r.height>0);for(const r of rects)text.push({text:node.textContent.trim(),color:c.color,fontSize:parseFloat(c.fontSize),fontWeight:c.fontWeight,x:r.left-b.left,y:r.top-b.top,width:r.width,height:r.height});}
   return {width:b.width,height:b.height,text};
  });
  const hide=await page.addStyleTag({content:'.tv-frame *{color:transparent!important;text-shadow:none!important}'});
  const file=`output/playwright/scenic-background-${state}.png`;
  await page.locator('.tv-frame').screenshot({path:root+'/'+file,scale:'css',animations:'disabled'});await hide.evaluate(el=>el.remove());
  report.states.push({state,file,...geometry});
 }
 return report;
}
