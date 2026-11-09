import { version } from '../package.json';
import text from './credits.txt?raw';

// The holder is a pen name; the author's real name must never appear in a served file.
const copyright = 'Copyright © 2026 Fra. M.H.B.N.M. All rights reserved.';

console.log(`inkhk3.org ${version}\n${copyright}`);
console.log(text);
