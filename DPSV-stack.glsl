/*
	This code is released under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
	See : https://creativecommons.org/licenses/by-nc-sa/3.0/

	Although not required, we appreciate hearing (frederic.mora@unilim.fr) if you use this, 
	since that justifies the effort of making it available.
*/

/*
	-- Shading with a TOP tree with support for depth test --

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
#version 430

// Deferred Buffer: Must contain the fragment position in the world coordinates system
layout( binding = 0) uniform sampler2DArray deferredBuffer;

// Texture coordinate to read in the deferred buffer
in vec3 texCoord;

// fragment final color
layout (location = 0) out vec4 color;

// a TOP tree node
struct node {
	vec4 plane;
	uint link[4]; /* 0: positive child, 1: intersection child, 2: negative child (not used), 3: wedge angle */
};

// TOP tree buffer.
layout (std430, binding=13) restrict buffer TOPTree	{
	node nodes[]; 
};

// Buffer to read the root index
layout (std430, binding=29) restrict buffer TOPTreeRoot	{
	uint root; 
};


/* return 0 if p is in shadow, 1 otherwise
	p is the fragment in the world coordinates system with the light as origin
	normal is the surface normal at p
*/
float DPSV_stack( in vec3 p, in vec3 normal){ //avec distance uint
	uint stacksize = 0;
	// node stack
    uint stack[32];
    // light - p distance
	const float dist = length(p);

	// if we are back facing the light, querying the TOP tree is not necessary
	if ( dot( normal, -p) < 0.0 ) return 0.0;
 	
 	// start from root node index
	uint current = root;

	// find the location of p
	while(current>1){
		// pop
		const node n = nodes[ current ];
		
		// [EGSR2016] skip the current subtree if p is closest from the light than the geometry in the subtree
		if ( current%4==0 && dist < uintBitsToFloat(n.link[2]) ){  
			current = stacksize > 0 ? stack[ --stacksize ] : 1;
			continue;
		}

		// compute the signed distance from p to the current plane
		const float offset = dot(n.plane.xyz, p) + n.plane.w;

		// if an intersection child exists and if current is a capping plane or if it is a shadow plane and p is inside its wedge 
		if ( n.link[1]>0  &&  (current%4==3 || offset*offset / (dist*dist) < uintBitsToFloat(n.link[3] )  ) )
		   stack[ stacksize++ ] = n.link[1];
				
		// if p is in the positive halfspace of the plane
		if ( offset>0.0 ){
			// continue in the positive child if it exists	
			if (n.link[0]>0) current = n.link[0] ;
			// pop another node from the stack. If empty end the query with 1 (outside all shadow volumes)
			else current = stacksize>0 ? stack[ --stacksize ] : 1;										
		}
		else // otherwise p is in the negative halfspace
			// 0, p is inside a shadow volume. Otherwise continue in the negative child
			current = current%4==3 ? 0 : current+1;	
			
	}
	return float(current);
}

// must return the fragment position in the world space coordinates system
vec4 getFragmentPosition(){
	// coordinates should not be interpolated !
	return textureLod(deferredBuffer, /* TO COMPLETE */ );
}

// must return the fragment normal in the world coordinates system
vec3 getFragmentNormal(){
	return normalize( textureLod( deferredBuffer, /* TO COMPLETE */ ).xyz);
}

// return true if a fragment exists, otherwise false (no projected geometry)
bool fragmentExist( in vec4 frag ){
	// TO COMPLETE 
}

// must return the light position in the world space coordinates system
vec3 getLight(){
	// TO COMPLETE
}

void main()
{	
	vec4 pos = getFragmentPosition();
	if( fragmentExist(pos)==true )
	{
		vec3 normal = getFragmentNormal();
		vec3 light = getLight();
		float visibility = DPSV_stack(pos.xyz-light, normal); 
		
		/* You may want compute the final color using visiblity (0/1), light, normal and pos ! Or whatever you want.
		color = TO COMPLETE
		*/
	}
	else
		color=vec4(1);
}
	