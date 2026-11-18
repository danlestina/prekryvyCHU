const fs=require('fs'),vm=require('vm');let t=fs.readFileSync(process.argv[2],'utf8');
let m=t.match(/const decimalPlaces=n=>[\s\S]*?const getCat=/);if(!m)throw Error('Missing fmt');
let code=m[0].replace(/const getCat=$/,'');let ctx={};vm.runInNewContext(code+';this.roundedText=roundedText;this.fmt=fmt;',ctx);
for(const [n,x] of [[1111111.111111,'1111111'],[1.1111111111,'1.111'],[0.000011111111,'0.00001111'],[11.1111111111111,'11.11'],[0, '0'],[1234.5678,'1235'],[12345.6789,'12346'],[0.000000001111111,'0.000000001111']]){
 const got=ctx.roundedText(n);if(got!==x)throw Error(`${n}: expected ${x}, got ${got}`);}
console.log('TEST WEB 4 PLATNE CISLICE OK');