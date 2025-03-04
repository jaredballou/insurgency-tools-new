#ifndef __war3source_inavmeshladder_h__
#define __war3source_inavmeshladder_h__

#include "NavDirType.h"

namespace War3Source {
	class INavMeshLadder {
	public:
		virtual unsigned int GetID() = 0;
		virtual float GetWidth() = 0;
		virtual float GetLength() = 0;

		virtual float GetTopX() = 0;
		virtual float GetTopY() = 0;
		virtual float GetTopZ() = 0;

		virtual float GetBottomX() = 0;
		virtual float GetBottomY() = 0;
		virtual float GetBottomZ() = 0;

		virtual NavDirType GetDirection() = 0;
	
		virtual unsigned int GetTopForwardAreaID() = 0;
		virtual unsigned int GetTopLeftAreaID() = 0;
		virtual unsigned int GetTopRightAreaID() = 0;
		virtual unsigned int GetTopBehindAreaID() = 0;

		virtual unsigned int GetBottomAreaID() = 0;
	};
}

#endif