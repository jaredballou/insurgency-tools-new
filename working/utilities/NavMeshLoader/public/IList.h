#ifndef __war3source_ilist_h__
#define __war3source_ilist_h__
#include <cstddef>
//using namespace std;
namespace War3Source {
	template <class T> class IList {
	public:
		virtual bool Insert(T item, unsigned int index) = 0;
		virtual void Append(T item) = 0;
		virtual void Prepend(T item) = 0;
		virtual T At(unsigned int index) = 0;
		virtual std::size_t Size() = 0;
		virtual unsigned int Find(T item) = 0;
	};
}

#endif
