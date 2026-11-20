import { async } from '../Bsdkrun.Internal/foreign.js';

export const queryImpl = spec => async(signal => new Promise((resolve, reject) => {
  let close = () => {};
  const cancel = () => { close(); reject(Error('Database query interrupted')); };
  const timer = setTimeout(() => { close(); reject(Error('Database query timed out')); }, 45000);
  signal.addEventListener('abort', cancel, { once: true });
  (async () => {
    const { createConnection } = await import('mysql2/promise');
    const client = await createConnection(spec.url);
    close = () => client.destroy();
    try { const [rows] = await client.query({ sql: spec.sql, timeout: 30000 }); return Array.isArray(rows) ? rows.map(row => Object.values(row).map(String)) : []; }
    finally { await client.end(); }
  })().then(resolve, reject).finally(() => { clearTimeout(timer); signal.removeEventListener('abort', cancel); });
}));
