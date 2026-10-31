// PROPOSAL ONLY — NOT IMPLEMENTED. Invoked by playwright-cli run-code.
async (page) => {
  const root = '/Users/ghassenbrg/git/miraya/Creative Design/2026-10-29-beam-redesign';
  const errors=[]; page.on('pageerror',error=>errors.push(error.message));
  await page.goto('http://127.0.0.1:8841/?view=mac&state=ready');
  await page.emulateMedia({reducedMotion:'reduce'});
  await page.addStyleTag({content:'.preview-capture.tv-capture{width:1920px;max-width:none}.tv-wrap{width:1920px;max-width:none}'});
  const captures=[
    ['mac','ready','mac-ready',420,'light'],['mac','pairing','mac-pairing',420,'light'],
    ['mac','live','mac-live',420,'light'],['mac','permission','mac-error-recovery',420,'light'],
    ['mac','paused','mac-paused',420,'light'],['mac','ready','mac-compact',340,'light'],
    ['mac','live','mac-dark-live',420,'dark'],['mac','manual','mac-manual',420,'light'],
    ['mac','trusted','mac-trusted-devices',420,'light'],['mac','details','mac-connection-details',420,'light'],
    ['mac','media-ready','mac-direct-media-ready',420,'light'],['mac','media-live','mac-direct-media-live',420,'light'],
    ['tv','ready','tv-ready'],['tv','pairing','tv-pairing'],['tv','approval','tv-approval'],
    ['tv','live','tv-live'],['tv','controls','tv-controls'],['tv','paused','tv-paused'],
    ['tv','details','tv-details'],['tv','picture','tv-picture-modes'],['tv','trusted','tv-trusted-macs'],
    ['tv','media-controls','tv-direct-media-controls'],['brand','identity','brand-board'],
    ['icons','platforms','icon-board'],['icons','small','small-icon-test'],['system','system','design-system-board']
  ];
  const report={status:'PROPOSAL ONLY — NOT IMPLEMENTED',captures:[],states:[],errors};
  for(const [view,state,name,width=420,theme='light'] of captures){
    await page.setViewportSize(view==='tv'?{width:2048,height:1500}:{width:1280,height:1040});
    await page.evaluate(({view,state,width,theme})=>window.beamReview.set(view,state,{width:String(width),theme,modal:null,tvReturn:['picture','margin','volume'].includes(state)?'controls':'ready',sourceKind:state.startsWith('media-')?'media':'display',source:'Built-in Display'}),{view,state,width,theme});
    await page.locator('.preview-capture img').evaluateAll(images=>Promise.all(images.map(img=>img.decode().catch(()=>{}))));
    await page.locator('.preview-capture').screenshot({path:`${root}/previews/${name}.png`,scale:'css',animations:'disabled'});
    report.captures.push({view,state,file:`previews/${name}.png`});
  }
  // Inspect every principal state at compact and standard widths; vertical
  // scrolling within native-window bodies and sheets is intentional.
  await page.setViewportSize({width:1280,height:1000});
  await page.addStyleTag({content:'.preview-capture.tv-capture{width:min(1180px,100%);max-width:100%}.tv-wrap{width:100%;max-width:100%}'});
  const states=await page.evaluate(()=>window.beamReview.states);
  for(const [view,list] of Object.entries(states))for(const [,state] of list)for(const width of view==='mac'?[340,420,540]:[1180,1920])for(const theme of view==='mac'?['light','dark']:['light']){
    await page.setViewportSize({width:width===1920?2048:1280,height:1300});
    if(view==='tv')await page.addStyleTag({content:'.preview-capture.tv-capture{width:'+width+'px;max-width:none}.tv-wrap{width:100%;max-width:none}'});
    await page.evaluate(({view,state,width,theme})=>window.beamReview.set(view,state,{width:String(width),theme,modal:null}),{view,state,width,theme});
    const check=await page.evaluate(()=>{
      const root=document.querySelector('.mac-window,.tv-frame');const r=root.getBoundingClientRect();
      const clipped=[...root.querySelectorAll('button,input,select,h1,.mac-digits,.tv-digits')].filter(x=>x.getClientRects().length).map(x=>({el:x,rect:x.getBoundingClientRect()})).filter(({rect})=>rect.left<r.left-2||rect.right>r.right+2).map(({el})=>el.textContent.trim().slice(0,75)||el.getAttribute('aria-label'));
      const broken=[...root.querySelectorAll('img')].filter(x=>x.complete&&!x.naturalWidth).map(x=>x.getAttribute('src'));
      return {clipped,broken,h1:root.querySelector('h1')?.textContent,footerVisible:!root.querySelector('.mac-footer')||root.querySelector('.mac-footer').getBoundingClientRect().bottom<=r.bottom+1};
    });
    report.states.push({view,state,width,theme,...check});
  }
  await page.goto('http://127.0.0.1:8841/review-overview.html');
  await page.setViewportSize({width:1800,height:1400});
  await page.locator('.overview img').evaluateAll(images=>Promise.all(images.map(img=>img.decode().catch(()=>{}))));
  await page.locator('.overview').screenshot({path:`${root}/previews/review-overview.png`,scale:'css',animations:'disabled'});
  report.captures.push({view:'overview',state:'board',file:'previews/review-overview.png'});
  return report;
}
