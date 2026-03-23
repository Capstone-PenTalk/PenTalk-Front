const http = require('http');
const { Server } = require('socket.io');

const PORT = process.env.PORT || 3000;

const server = http.createServer();
const io = new Server(server, {
  cors: { origin: '*' },
  transports: ['websocket'],
});

io.on('connection', (socket) => {
  const role = socket.handshake.query.role || 'unknown';
  const token = socket.handshake.auth?.token || socket.handshake.query.token;
  console.log('connected', socket.id, { role, token: token ? 'present' : 'missing' });

  socket.on('join_room', ({ roomId, userId, role }) => {
    console.log('join_room', { roomId, userId, role });
    if (roomId) {
      socket.join(roomId);
    }
  });

  socket.on('draw:append', (payload) => {
    console.log('draw:append', payload);
    const roomId = payload?.r || payload?.roomId;
    if (roomId) {
      socket.to(roomId).emit('draw:append', payload);
    } else {
      socket.broadcast.emit('draw:append', payload);
    }
  });

  socket.on('draw:clear', (payload) => {
    console.log('draw:clear', payload);
    const roomId = payload?.r || payload?.roomId;
    if (roomId) {
      socket.to(roomId).emit('draw:clear', payload);
    } else {
      socket.broadcast.emit('draw:clear', payload);
    }
  });

  socket.on('disconnect', (reason) => {
    console.log('disconnected', socket.id, reason);
  });
});

server.listen(PORT, () => {
  console.log(`socket server listening on :${PORT}`);
});
