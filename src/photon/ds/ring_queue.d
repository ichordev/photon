module photon.ds.ring_queue;



struct RingQueue(T, Event)
{
    T* store;
    size_t length;
    size_t fetch, insert, size;
    Event cts, rtr; // clear to send, ready to recieve
    shared uint refCount;
    
    this(size_t capacity, Event cts, Event rtr)
    {
        store = cast(T*)malloc(T.sizeof * capacity);
        length = capacity;
        size = 0;
        this.cts = move(cts);
        this.rtr = move(rtr);
        refCount = 1;
    }

    void push(T ctx)
    {
        store[insert++] = ctx;
        if (insert == length) insert = 0;
        size += 1;
    }

    T pop()
    {
        auto ret = store[fetch++];
        if (fetch == length) fetch = 0;
        size -= 1;
        return ret;
    }

    bool empty(){ return size == 0; }

    void retain() {

    }
}
