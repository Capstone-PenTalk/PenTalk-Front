const { io } = require('socket.io-client');

const url = process.env.SOCKET_URL || 'http://localhost:3000';
const role = process.env.ROLE || 'teacher';
const token = process.env.TOKEN || 'dev-token';
const roomId = process.env.ROOM_ID || 'room_demo';
const userId = process.env.USER_ID || 'user_demo';

const socket = io(url, {
  transports: ['websocket'],
  query: { role },
  auth: { token },
});

socket.on('connect', () => {
  console.log('connected', socket.id);
  socket.emit('join_room', { roomId, userId, role });

  const strokeId = Date.now();
  socket.emit('draw:append', {
    e: 'ds',
    sId: strokeId,
    x: 0.1,
    y: 0.1,
    c: '#FF0000',
    w: 2.5,
    r: roomId,
  });
  socket.emit('draw:append', {
    e: 'dm',
    sId: strokeId,
    x: 0.2,
    y: 0.2,
    r: roomId,
  });
  socket.emit('draw:append', {
    e: 'de',
    sId: strokeId,
    pts: [
      { x: 0.1, y: 0.1 },
      { x: 0.2, y: 0.2 },
    ],
    r: roomId,
  });
});

socket.on('draw:append', (payload) => {
  console.log('[recv] draw:append', payload);
});

socket.on('draw:clear', (payload) => {
  console.log('[recv] draw:clear', payload);
});

socket.on('connect_error', (err) => {
  console.error('connect_error', err.message);
});

socket.on('disconnect', (reason) => {
  console.log('disconnected', reason);
});
