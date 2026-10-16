const WebSocket = require('ws');
const assert = require('assert');
const { startServer, server, stopCleanup } = require('./server');

const TEST_PORT = 8090;
const WS_URL = `ws://localhost:${TEST_PORT}`;

function nextMessage(ws) {
  return new Promise((resolve, reject) => {
    const onMsg = (raw) => {
      cleanup();
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(err);
      }
    };
    const onErr = (err) => {
      cleanup();
      reject(err);
    };
    function cleanup() {
      ws.off('message', onMsg);
      ws.off('error', onErr);
    }
    ws.on('message', onMsg);
    ws.on('error', onErr);
  });
}

function connectClient() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

async function runTests() {
  await startServer(TEST_PORT);

  let hostWs = null;
  let viewerWs = null;
  let roomCode = null;

  try {
    // 1. create returns a 6-digit code
    hostWs = await connectClient();
    const pCreate = nextMessage(hostWs);
    hostWs.send(JSON.stringify({ type: 'create' }));
    const createMsg = await pCreate;
    assert.strictEqual(createMsg.type, 'created');
    assert(createMsg.code && /^\d{6}$/.test(createMsg.code), 'Code is not 6 digits: ' + createMsg.code);
    roomCode = createMsg.code;
    console.log('PASS: 1. create returns a 6-digit code');

    // 2. wrong code returns invalid_code
    const wrongWs = await connectClient();
    const pWrong = nextMessage(wrongWs);
    wrongWs.send(JSON.stringify({ type: 'join', code: '000000' }));
    const wrongMsg = await pWrong;
    assert.strictEqual(wrongMsg.type, 'error');
    assert.strictEqual(wrongMsg.message, 'invalid_code');
    wrongWs.close();
    console.log('PASS: 2. wrong code returns invalid_code');

    // 3. valid join gives host join-request and viewer waiting
    viewerWs = await connectClient();
    const pViewerWaiting = nextMessage(viewerWs);
    const pHostJoinReq = nextMessage(hostWs);
    viewerWs.send(JSON.stringify({ type: 'join', code: roomCode }));
    const [waitMsg, reqMsg] = await Promise.all([pViewerWaiting, pHostJoinReq]);
    assert.strictEqual(waitMsg.type, 'waiting');
    assert.strictEqual(reqMsg.type, 'join-request');
    console.log('PASS: 3. valid join gives host join-request and viewer waiting');

    // 4. accept gives viewer accepted
    const pAccepted = nextMessage(viewerWs);
    hostWs.send(JSON.stringify({ type: 'accept' }));
    const acceptedMsg = await pAccepted;
    assert.strictEqual(acceptedMsg.type, 'accepted');
    console.log('PASS: 4. accept gives viewer accepted');

    // 5. offer from host reaches viewer unchanged
    const pOffer = nextMessage(viewerWs);
    const testOfferSdp = 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
    hostWs.send(JSON.stringify({ type: 'offer', sdp: testOfferSdp }));
    const offerMsg = await pOffer;
    assert.strictEqual(offerMsg.type, 'offer');
    assert.strictEqual(offerMsg.sdp, testOfferSdp);
    console.log('PASS: 5. offer from host reaches viewer unchanged');

    // 6. answer from viewer reaches host unchanged
    const pAnswer = nextMessage(hostWs);
    const testAnswerSdp = 'v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
    viewerWs.send(JSON.stringify({ type: 'answer', sdp: testAnswerSdp }));
    const answerMsg = await pAnswer;
    assert.strictEqual(answerMsg.type, 'answer');
    assert.strictEqual(answerMsg.sdp, testAnswerSdp);
    console.log('PASS: 6. answer from viewer reaches host unchanged');

    // 7. end gives the other side ended
    const pEnded = nextMessage(hostWs);
    viewerWs.send(JSON.stringify({ type: 'end' }));
    const endedMsg = await pEnded;
    assert.strictEqual(endedMsg.type, 'ended');
    console.log('PASS: 7. end gives the other side ended');

    hostWs.close();
    viewerWs.close();

    // 8. 5 wrong codes returns too_many_attempts
    const bruteWs = await connectClient();
    for (let i = 1; i <= 4; i++) {
      const pAtt = nextMessage(bruteWs);
      bruteWs.send(JSON.stringify({ type: 'join', code: '11111' + i }));
      const attMsg = await pAtt;
      assert.strictEqual(attMsg.type, 'error');
      assert.strictEqual(attMsg.message, 'invalid_code');
    }
    const pAtt5 = nextMessage(bruteWs);
    const pClose = new Promise(resolve => bruteWs.once('close', resolve));
    bruteWs.send(JSON.stringify({ type: 'join', code: '111115' }));
    const att5Msg = await pAtt5;
    assert.strictEqual(att5Msg.type, 'error');
    assert.strictEqual(att5Msg.message, 'too_many_attempts');
    await pClose;
    console.log('PASS: 8. 5 wrong codes returns too_many_attempts');

    console.log('\nAll 8 checks passed successfully!');
  } catch (err) {
    console.error('FAIL:', err);
    process.exitCode = 1;
  } finally {
    stopCleanup();
    if (hostWs) hostWs.close();
    if (viewerWs) viewerWs.close();
    server.close(() => {
      process.exit(process.exitCode || 0);
    });
  }
}

runTests();
