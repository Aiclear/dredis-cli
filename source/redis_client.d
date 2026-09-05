module redis_client;

import std.stdio;
import std.socket;
import std.exception;
import std.conv;

import redis_type;
import byte_buffer;
import std.parallelism;

// client default buffer size 2MB
const size_t DEFAULT_CLIENT_BUFFER_SIZE = 2 * 1024 * 1024;

class RedisClient {

    private XSocket socket;
    private ByteBuffer buffer;
    ServerInfo serverInfo;

    this(Socket socket) {
        this.socket = new XSocket(socket);
        this.buffer = ByteBuffer.create(DEFAULT_CLIENT_BUFFER_SIZE);
    }

    void printServerInfo() {
        writeln(serverInfo);
    }

    void close() {
        if (socket !is null) {
            socket.socket.close();
        }
    }

    static RedisClient connect(string ip, ushort port) {
        return handshake(ip, port, null);
    }

    static RedisClient connect(string ip, ushort port, string password) {
        return handshake(ip, port, password);
    }

    RedisType execCmd(const string command) {
        // encode command with resp protoco type
        redis_type.encode(command, buffer);
        socket.write(buffer);

        // read response from server
        socket.read(buffer);
        return decode_(buffer);
    }
}

struct ServerInfo {
    string server;
    string version_;
    string proto;
}

private RedisClient handshake(string ip, ushort port, string password) {
    auto clientSocket = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);

    // connect to redis server with tcp commu
    auto redisServerAddr = new InternetAddress(ip, port);
    clientSocket.connect(redisServerAddr);
    // build hello command 
    Hello helloCmd;
    if (password.length) {
        helloCmd.auth = Auth(password);
    }

    // send hello command and confirm resp version
    auto sendRes = clientSocket.send(helloCmd.encode());
    if (Socket.ERROR == sendRes) {
        enforce!Exception("send hello command to server recv error");
    }

    // handle hello cmd response
    ubyte[] tmpBuf = new ubyte[1024];
    auto c = clientSocket.receive(tmpBuf);
    if (Socket.ERROR == c) {
        enforce!Exception("receive data from server error");
    }
    ByteBuffer tmpBuffer = ByteBuffer.createWith(tmpBuf);
    auto redisServerInfo = decode_(tmpBuffer);

    ServerInfo serverInfo;
    if (auto map = cast(Maps) redisServerInfo) {
        foreach (k, v; map.value) {
            if (auto bs = cast(BulkStrings) k) {
                if ("server" == bs.value) {
                    serverInfo.server = (cast(BulkStrings) v).value.get();
                } else if ("proto" == bs.value) {
                    serverInfo.proto = to!string((cast(Integers) v).value);
                } else if ("version" == bs.value) {
                    serverInfo.version_ = (cast(BulkStrings) v).value.get();
                }
            }
        }
    }

    // init redis client by sever response info
    auto redisClient = new RedisClient(clientSocket);
    redisClient.serverInfo = serverInfo;

    return redisClient;
}

class XSocket {
    Socket socket;

    this(Socket socket) {
        this.socket = socket;
    }

    public void read(ByteBuffer buffer) {
        auto lenBytes = this.socket.receive(buffer.recvBufferSlice());
        buffer.onRecv(lenBytes);
    }

    public void write(ByteBuffer buffer) {
        this.socket.send(buffer.sendBufferSlice());
        // write data to socket, then compact buffer to free space
        buffer.compact();
    }
}
