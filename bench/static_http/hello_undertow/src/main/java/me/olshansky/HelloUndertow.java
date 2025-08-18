package me.olshansky;

import java.net.Inet4Address;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;

import org.xnio.BufferAllocator;
import org.xnio.ByteBufferSlicePool;
import org.xnio.ChannelListener;
import org.xnio.ChannelListeners;
import org.xnio.OptionMap;
import org.xnio.Options;
import org.xnio.Pool;
import org.xnio.StreamConnection;
import org.xnio.Xnio;
import org.xnio.XnioWorker;
import org.xnio.channels.AcceptingChannel;
import org.xnio.ssl.JsseXnioSsl;
import org.xnio.ssl.SslConnection;
import org.xnio.ssl.XnioSsl;

import io.undertow.Undertow;
import io.undertow.Undertow.ListenerType;
import io.undertow.UndertowOptions;
import io.undertow.server.HttpHandler;
import io.undertow.server.HttpServerExchange;
import io.undertow.server.protocol.http.HttpOpenListener;
import io.undertow.util.Headers;
import org.xnio.Xnio;
import org.xnio.XnioWorker;
import org.xnio.OptionMap;

public class HelloUndertow {
    public static void main(final String[] args) throws Exception {
        final int bufferSize = 256;
        final int buffersPerRegion = 100;
        int ioThreads = Runtime.getRuntime().availableProcessors();
        int workers = Runtime.getRuntime().availableProcessors();
        if (args.length > 0) {
            ioThreads = Integer.parseInt(args[0]);
            workers = Integer.parseInt(args[1]);
        }
        HttpHandler rootHandler = new HttpHandler() {
            @Override
            public void handleRequest(final HttpServerExchange exchange) throws Exception {
                exchange.getResponseHeaders().put(Headers.CONTENT_TYPE, "text/plain");
                exchange.getResponseSender().send("Hello World");
            }
        };
        Xnio xnio = Xnio.getInstance();

        XnioWorker worker = xnio.createWorker(OptionMap.builder()
                .set(Options.WORKER_IO_THREADS, workers)
                .set(Options.WORKER_TASK_CORE_THREADS, workers)
                .set(Options.WORKER_TASK_MAX_THREADS, workers)
                .set(Options.TCP_NODELAY, true)
                .getMap());

        OptionMap serverOptions = OptionMap.builder().getMap();

        OptionMap socketOptions = OptionMap.builder()
                .set(Options.WORKER_IO_THREADS, workers)
                .set(Options.TCP_NODELAY, true)
                .set(Options.REUSE_ADDRESSES, true)
                .getMap();

        Pool<ByteBuffer> buffers = new ByteBufferSlicePool(BufferAllocator.DIRECT_BYTE_BUFFER_ALLOCATOR, bufferSize, bufferSize * buffersPerRegion);

        HttpOpenListener openListener = new HttpOpenListener(buffers, OptionMap.builder().set(UndertowOptions.BUFFER_PIPELINED_DATA, true).addAll(serverOptions).getMap());
        openListener.setRootHandler(rootHandler);
        ChannelListener<AcceptingChannel<StreamConnection>> acceptListener = ChannelListeners.openListenerAdapter(openListener);
        AcceptingChannel<? extends StreamConnection> server = worker.createStreamConnectionServer(new InetSocketAddress(Inet4Address.getByName("127.0.0.1"), 8080), acceptListener, socketOptions);
        server.resumeAccepts();
    }
}
