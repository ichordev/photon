module photon.ds.common;

ref T unshared(T)(ref shared T value) {
     return *cast(T*)&value;
}

interface WorkQueue(T) {
    shared void push(T item);
    shared T pop(); // blocks if empty
    shared bool tryPop(ref T item); // non-blocking
}
