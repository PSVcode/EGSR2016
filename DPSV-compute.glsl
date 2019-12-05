/*
	This code is released under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
	See : https://creativecommons.org/licenses/by-nc-sa/3.0/

	Although not required, we appreciate hearing (frederic.mora@unilim.fr) if you use this, 
	since that justifies the effort of making it available.
*/

/*
	-- Building a TOP tree with support for depth test and stackless traversal--
	This is the compute shader implementation related to the Eurographics Symposium on Rendering 2016 paper:
	Deep Partitioned Shadow Volumes using Stackless and Hybrid Traversals, by Frédéric Mora, Julien Gerhards, Lilian Aveneau and Djamchid Ghazanfarpour
	@inproceedings {DPSV2016,
  		booktitle = {Eurographics Symposium on Rendering - Experimental Ideas & Implementations},
  		editor = {Elmar Eisemann and Eugene Fiume},
  		title = {Deep Partitioned Shadow Volumes using Stackless and Hybrid Traversals},
  		author = {Mora, Frédéric and Gerhards, Julien and Aveneau, Lilian and Ghazanfarpour, Djamchid},
  		year = {2016},
  		publisher = {The Eurographics Association},
	} 
	Please, have a look at the comments to know how to use this shader
	All the comments "TO COMPLETE" must be replaced with few lines of code depending on your own application
	All the comments "[EGSR2016]" point out the changes introduced in the EGSR2016 paper compare to the former EG2015 paper.
*/
#version 430 core

layout (local_size_x = 512,local_size_y = 1,local_size_z = 1) 	in;


// comment if the geometry does not support front face culling
#define FFCULLING 

// basic triangle data structure
struct triangle {
	vec4 a;
	vec4 b;
	vec4 c;
};

// a TOP tree node
struct node {
	vec4 plane;
	uint link[4]; /* 0: positive child, 1: intersection child, 2: negative child (not used), 3: wedge angle */
};

// Number of threads per work group
// 512 is the value used in the Partitioned Shadow Volumes paper. You may want to change.
layout (local_size_x = 512,local_size_y = 1,local_size_z = 1) 	in;


/* bind a buffer where to find all the triangles. This depends on your own program
   For models with less than 600k triangles, the thread scheduling is generally sufficient
   to induce a random insertion of the triangles in the TOP tree. Otherwise you may want to add
   a permutation list as described in the PSV paper.
layout (...
TO COMPLETE
*/

/* TOP tree buffer.
   The allocation size has to be 4*(n+1)*sizeof(node) for n triangles.
   Index 0 is used to represent a leaf. Since nodes index are tested modulo 4
   it is more convenient to write inner nodes from index 4.
*/
layout (std430, binding=13) restrict buffer TOPTree	{
	node nodes[]; 
};


// Buffer to write/read the root index
layout (std430, binding=29) restrict buffer TOPTreeRoot	{
	uint root; // initalized to 0
};


/* AtomicAdd counters
   node is the first position available in the TOPTree buffer
   triangle is the first position of a triangle waiting for insertion. It is only used by main_persistant()
*/
layout (std430,binding=30) buffer util { 
	uint node; // initialized to 4
	uint triangle;  // initialized to 0
} index;


// must return the light position in the world space coordinates system
vec3 getLight(){
	// TO COMPLETE
}

// must return the number of triangles
uint getTriangleNumber(){
	// TO COMPLETE
}

// must return the i th triangle in the world space coordinates system
triangle getTriangle( in uint i ){
	 // TO COMPLETE
}


// return the plane defined by the light and the segment v1v2 (assuming the light is the origin)
vec4 computeShadowPlane( in vec3 v1, in vec3 v2)
{
	// due to numerical inacurracy, the plane light-v1-v2 may be different from the plane light-v2-v1
	// thus it is safer to consider the vertices always in the same order
	if ( v1.x < v2.x ) // partial test, but generally it is sufficient in practice. Otherwise y-axis and z-axis has to be tested
		return vec4(  normalize( cross(v1, v2-v1) ), 0.0);
	else
		return vec4( -normalize( cross(v2, v1-v2) ), 0.0);

}

/* return the position of the triangle ABC wrt the plane.
	-3: ABC is in the negative halfspace of the plane
	 0: ABC is intersected by the plane
	+3: ABC is in the positive halfspace of the plane
*/
int trianglePosition(in vec3 A, in vec3 B, in vec3 C, in vec4 plane)
{
	const int sig = int(sign( dot(plane, vec4(A, 1)) )) +
					int(sign( dot(plane, vec4(B, 1)) )) +
					int(sign( dot(plane, vec4(C, 1)) )) ;

	return abs(sig)==3 ? sig : 0;
}

/* return the angle (its squared sine) that defines the wedge enclosing triangle ABC from the light wrt a shadow plane
   (assuming the light is the origin)
*/
float wedgeAngle( in vec4 plane, in vec3 A, in vec3 B, in vec3 C)
{
	float d1 = dot(plane, vec4(A, 1)); // distance from A to the shadow plane
	float d2 = dot(plane, vec4(B, 1)); // distance from B to the shadow plane
	float d3 = dot(plane, vec4(C, 1)); // distance from C to the shadow plane
	// recall that a shadow plane contains the light
	d1 = d1*d1 / dot(A,A); // squared sine of the angle between the shadow plane and the segment lightA
	d2 = d2*d2 / dot(B,B); // squared sine of the angle between the shadow plane and the segment lightB
	d3 = d3*d3 / dot(C,C); // squared sine of the angle between the shadow plane and the segment lightC
	
    return(max(d1,max(d2,d3))); // return the maximum of the 3 (squared) sines
}


/* Distance to a triangle function by inigo quilez - iq/2013
	 https://www.shadertoy.com/view/4sXXRN
	 License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
	 https://creativecommons.org/licenses/by-nc-sa/3.0/
*/
float dot2( in vec3 v ) { return dot(v,v); }

float tri2LightDistance( in vec3 v1, in vec3 v2, in vec3 v3, in vec3 p )
{
    const vec3 v21 = v2 - v1; vec3 p1 = p - v1;
    const vec3 v32 = v3 - v2; vec3 p2 = p - v2;
    const vec3 v13 = v1 - v3; vec3 p3 = p - v3;
    const vec3 nor = cross( v21, v13 );

    return sqrt( (sign(dot(cross(v21,nor),p1)) + 
                  sign(dot(cross(v32,nor),p2)) + 
                  sign(dot(cross(v13,nor),p3))<2.0) 
                  ?
                  min( min( 
                  dot2(v21*clamp(dot(v21,p1)/dot2(v21),0.0,1.0)-p1), 
                  dot2(v32*clamp(dot(v32,p2)/dot2(v32),0.0,1.0)-p2) ), 
                  dot2(v13*clamp(dot(v13,p3)/dot2(v13),0.0,1.0)-p3) )
                  :
                  dot(nor,p1)*dot(nor,p1)/dot2(nor) );
}


/*  TOP Tree building algorithm
	A thread pick up the i th triangle in the triangles buffer and find its location in the TOP tree.
	Unless the triangle is not visible from the light, the related shadow volume is merged to the tree.
*/
void TOPTREE_mergeShadowVolumeCastByTriangle( in uint i ){
		// get the light position in the world coordinates system
		const vec3 light = getLight();
		// get triangle i in the world coordinates system
		const triangle T = getTriangle(i);
		// vertices translation to make the light the origin (this is only to simplify the computations)
		const vec3 A  = T.a.xyz - light;
		const vec3 B  = T.b.xyz - light;
		const vec3 C  = T.c.xyz - light;
		// compute the capping plane equation (i.e. the supporting plane of triangle ABC)
		const vec3 norm = normalize( cross(C-A, B-A) );
		const vec4 capping_plane = vec4( norm, -dot(norm,A) );

#ifdef FFCULLING
		if ( capping_plane.w < 0.0 ) // Front Face Culling enable
#endif
		{
			// book 4 nodes in the TOP tree buffer to represent the SV generated by the light and triangle ABC 
			const uint insertion = atomicAdd(index.node, 4);
			node sp1,sp2,sp3,cp;
			// initialize the 4 nodes with the 3 shadow planes and the capping plane
			sp1.plane 		= computeShadowPlane(A, B);
			sp2.plane 		= computeShadowPlane(B, C);
			sp3.plane 		= computeShadowPlane(C, A);
			cp.plane 	    = -capping_plane;

#ifndef FFCULLING 
			if ( capping_plane.w > 0.0 ) // correct SV orientation for triangles front facing the light
			{
				sp1.plane = -sp1.plane;
				sp2.plane = -sp2.plane;
				sp3.plane = -sp3.plane;
				cp.plane  = -cp.plane;
			}	
#endif
			// slightly translate the capping plane away from the light to get ride of self shading artifacts
			cp.plane.w += 0.0001;

			const float distance = tri2LightDistance(A, B, C, vec3(0.0) );

			// init nodes
			sp1.link[0] = 0;		sp1.link[1] = 0;		sp1.link[2] = floatBitsToUint(distance); 		sp1.link[3] = 0;
			sp2.link[0] = 0;		sp2.link[1] = 0;		sp2.link[2] = 0;  	       		                sp2.link[3] = 0;
			sp3.link[0] = 0;		sp3.link[1] = 0;		sp3.link[2] = 0;        	                    sp3.link[3] = 0;
			cp.link[0]  = 0;	    cp.link[1]  = 0;    	cp.link[2]  = 0;			                 	cp.link[3]  = 0;
			
			// write the nodes in the array. Notice that this four node are connected by their negative child. 
			// However we do not use link[2]. Instead we will compute the negative index on the fly to avoid a buffer read
			nodes[insertion  ] = sp1;
			nodes[insertion+1] = sp2;
			nodes[insertion+2] = sp3;
			nodes[insertion+3] = cp;

			// if root equals 0, the TOP tree is empty and root is replaced by insertion that becomes the new root index.
			// Otherwise we simply get the root index of the TOP tree
			uint current = atomicCompSwap(root, 0, insertion);

			// [EGSR2016] - stackless support - holds the parent node of the last intersection subtree visited by the triangle
			uint lastsubroot = 1;

			// find the triangle location (except if the tree was empty)
			while( current != 0)
			{
				// compute the triangle position wrt the current plane
				const int pos = trianglePosition(A, B, C, nodes[current].plane);

				// [EGSR2106] - depth test support - update the distance from the light each time a new shadow volume is visited
				if (current%4==0)
					atomicMin(nodes[current].link[2], floatBitsToUint(distance) );
						
				if(pos<0) // the triangle is fully in the negative halfspace, compute the negative index
					if (current%4==3) current=0; // if the negative child is a leaf, the triangle is inside a shadow volume. This is an early termination case without merging the shadow volume.
					else ++current;	// otherwise, continue in the negative child	
				else
					if(pos>0) // the triangle is fully in the positive halfspace
						// if link[0] equals 0, the positive child is a leaf. Thus 0 is replaced by insertion, merging the shadow volume
						// cast by ABC. Otherwise we simply get the positive child index.
						current = atomicCompSwap(nodes[current].link[0], 0, insertion);
					else // the current plane intersects the triangle 
					{
						// [EGSR2016] - stackless support - the triangle descends in an intersection subtree, update lastsubroot
						lastsubroot = current;
						if ( current%4<3 ) // if the current plane is a shadow plane (wedge optimization is not relevant for the capping plane)
							atomicMax(nodes[current].link[3], floatBitsToUint(wedgeAngle(nodes[current].plane, A, B, C)));	// update the wedge angle
						// continue in the intersection child. If it equals 0, it is a leaf. Thus 0 is replaced by insertion, merging the shadow volume
						// cast by ABC. Otherwise, we simply get the intersection child index
						current = atomicCompSwap(nodes[current].link[1], 0, insertion);						
					}
			}
			// [EGSR2016] - stackless support - write the parent node index of the last intersection subtree visited by the triangle ABC
			nodes[insertion+2].link[2] = lastsubroot;
		}
}



/*
  Very rough persistant style variation. A thread merges triangles as long as triangles remain.
  We use a glDispatchCompute(32,1,1) with this one. 
*/
void main(void)	
{
	const uint size = getTriangleNumber();
	uint k;
	for(k=0;k<size;k++)
	{
		// get the index of the triangle to merge in the TOP tree
		uint i = atomicAdd(index.triangle, 1);
		if (i>=size) break; // no triangle left
		// merge triangle i in the TOP tree
		TOPTREE_mergeShadowVolumeCastByTriangle(i);
	}
}
