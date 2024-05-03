module photon.ds.common;

ref T unshared(T)(ref shared  T value) 
if (is(T == class)) {
     return *cast(T*)&value;
}

ref T* unshared(T)(ref shared(T)* value) {
     return *cast(T**)&value;
}

// intrusive list helper
T removeFromList(T)(T head, T item) {
	if (head == item) return head.next;
	else {
		auto p = head;
		while(p.next) {
			if (p.next == item)
				p.next = item.next;
			else 
				p = p.next;
		}
		return head;
	}
}