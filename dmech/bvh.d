/*
Copyright (c) 2011-2013 Timur Gafarov 

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dmech.bvh;

private
{
    import std.array;
    import std.math;

    import dlib.core.compound;

    import dlib.math.utils;
    import dlib.math.vector;

    import dlib.geometry.aabb;
    import dlib.geometry.sphere;
    import dlib.geometry.triangle;
    import dlib.geometry.trimesh;
    import dlib.geometry.ray;
}

/*
 * Bounding Volume Hierarchy implementation
 */

// Returns the axis that has the largest length
Axis boxGetMainAxis(AABB box)
{
    float xl = box.size.x;
    float yl = box.size.y;
    float zl = box.size.z;
         
    if (xl < yl)
    {
        if (yl < zl)
           return Axis.z;
        return Axis.y;
    }
    else if (xl < zl)
        return Axis.z;
    return Axis.x;        
}

struct SplitPlane
{
    public:
    float split;
    Axis axis;
    
    this(float s, Axis ax)
    {
        split = s;
        axis = ax;
    }
}

SplitPlane boxGetSplitPlaneForAxis(AABB box, Axis a)
{
    return SplitPlane(box.center[a], a);
}

Compound!(AABB, AABB) boxSplitWithPlane(AABB box, SplitPlane sp)
{
    Vector3f minLP = box.pmin;
    Vector3f maxLP = box.pmax;
    maxLP[sp.axis] = sp.split;
    
    Vector3f minRP = box.pmin;
    Vector3f maxRP = box.pmax;
    minRP[sp.axis] = sp.split;

    AABB leftB = boxFromMinMaxPoints(minLP, maxLP);
    AABB rightB = boxFromMinMaxPoints(minRP, maxRP);

    return compound(leftB, rightB);
}

AABB boxFromTriangles(Triangle[] tris)
{
    Vector3f pmin = tris[0].boundingBox.pmin;
    Vector3f pmax = pmin;
    
    void adjustMinPoint(Vector3f p)
    {    
        if (p.x < pmin.x) pmin.x = p.x;
        if (p.y < pmin.y) pmin.y = p.y;
        if (p.z < pmin.z) pmin.z = p.z;
    }
    
    void adjustMaxPoint(Vector3f p)
    {
        if (p.x > pmax.x) pmax.x = p.x;
        if (p.y > pmax.y) pmax.y = p.y;
        if (p.z > pmax.z) pmax.z = p.z;
    }

    foreach(ref tri; tris)
    {
        adjustMinPoint(tri.boundingBox.pmin);
        adjustMaxPoint(tri.boundingBox.pmax);
    }
    
    return boxFromMinMaxPoints(pmin, pmax);
}

class BVHNode
{
    Triangle[] tris;
    AABB aabb;
    BVHNode[2] child;
    uint userData;

    this(Triangle[] t)
    {
        tris = t;
        aabb = boxFromTriangles(tris);
    }
}

void traverseBySphere(BVHNode node, ref Sphere sphere, void delegate(ref Triangle) func)
{
    Vector3f cn;
    float pd;
    if (node.aabb.intersectsSphere(sphere, cn, pd))
    {
        if (node.child[0] !is null)
            node.child[0].traverseBySphere(sphere, func);
        if (node.child[1] !is null)
            node.child[1].traverseBySphere(sphere, func);

        foreach(ref tri; node.tris)
            func(tri);
    }
}

void traverse(BVHNode node, void delegate(BVHNode) func)
{
    if (node.child[0] !is null)
        node.child[0].traverse(func);
    if (node.child[1] !is null)
        node.child[1].traverse(func);

    func(node);
}

void traverseByRay(BVHNode node, Ray ray, void delegate(ref Triangle) func)
{
    float it = 0.0f;
    if (node.aabb.intersectsSegment(ray.p0, ray.p1, it))
    {
        if (node.child[0] !is null)
            node.child[0].traverseByRay(ray, func);
        if (node.child[1] !is null)
            node.child[1].traverseByRay(ray, func);

        foreach(ref tri; node.tris)
            func(tri);
    }
}

// TODO:
// - support multithreading (2 children = 2 threads)
// - add ESC (Early Split Clipping)
enum Heuristic
{
    HMA, // Half Main Axis
    SAH, // Surface Area Heuristic
    //ESC  // Early Split Clipping
}

final class BVHTree
{
    BVHNode root;

    this(Triangle[] tris, 
         uint maxObjectsPerNode = 8,
         Heuristic splitHeuristic = Heuristic.SAH)
    {
        root = construct(tris, maxObjectsPerNode, splitHeuristic);
    }

    BVHNode construct(
         Triangle[] tris, 
         uint maxObjectsPerNode,
         Heuristic splitHeuristic)
    {
        AABB box = boxFromTriangles(tris);
        
        SplitPlane sp;
        if (splitHeuristic == Heuristic.HMA)
            sp = getHalfMainAxisSplitPlane(tris, box);
        else if (splitHeuristic == Heuristic.SAH)
            sp = getSAHSplitPlane(tris, box);
        else
            assert(0, "BVH: unsupported split heuristic");
            
        auto boxes = boxSplitWithPlane(box, sp);

        Triangle[] leftTris;
        Triangle[] rightTris;
    
        foreach(tri; tris)
        {
            if (boxes[0].intersectsAABB(tri.boundingBox))
                leftTris ~= tri;
            else if (boxes[1].intersectsAABB(tri.boundingBox))
                rightTris ~= tri;
        }
    
        BVHNode node = new BVHNode(tris);

        if (tris.length <= maxObjectsPerNode)
            return node;
        
        if (leftTris.length > 0 || rightTris.length > 0)
            node.tris = [];

        if (leftTris.length > 0)
            node.child[0] = construct(leftTris, maxObjectsPerNode, splitHeuristic);
        else
            node.child[0] = null;
    
        if (rightTris.length > 0)
            node.child[1] = construct(rightTris, maxObjectsPerNode, splitHeuristic);
        else
            node.child[1] = null;

        return node;    
    }

    SplitPlane getHalfMainAxisSplitPlane(ref Triangle[] tris, ref AABB box)
    {
        Axis axis = boxGetMainAxis(box);
        return boxGetSplitPlaneForAxis(box, axis);
    }

    SplitPlane getSAHSplitPlane(ref Triangle[] tris, ref AABB box)
    {
        Axis axis = boxGetMainAxis(box);
        
        float minAlongSplitPlane = box.pmin[axis];
        float maxAlongSplitPlane = box.pmax[axis];
        
        float bestSAHCost = float.nan;
        float bestSplitPoint = float.nan;

        int iterations = 12;
        foreach (i; 0..iterations)
        {
            float valueOfSplit = minAlongSplitPlane + 
                               ((maxAlongSplitPlane - minAlongSplitPlane) / (iterations + 1.0f) * (i + 1.0f));

            SplitPlane SAHSplitPlane = SplitPlane(valueOfSplit, axis);
            auto boxes = boxSplitWithPlane(box, SAHSplitPlane);

            uint leftTrisLength = 0;
            uint rightTrisLength = 0;

            foreach(tri; tris)
            {
                if (boxes[0].intersectsAABB(tri.boundingBox))
                    leftTrisLength++;
                else if (boxes[1].intersectsAABB(tri.boundingBox))
                    rightTrisLength++;
            }

            if (leftTrisLength > 0 && rightTrisLength > 0)
            {
                float SAHCost = getSAHCost(boxes[0], leftTrisLength, 
                                           boxes[1], rightTrisLength, box);

                if (bestSAHCost.isNaN || SAHCost < bestSAHCost)
                {
                    bestSAHCost = SAHCost;
                    bestSplitPoint = valueOfSplit;
                }
            }
        }
        
        return SplitPlane(bestSplitPoint, axis);
    }

    float getSAHCost(AABB leftBox, uint numLeftObjects, 
                     AABB rightBox, uint numRightObjects,
                     AABB parentBox)
    {
        return getSurfaceArea(leftBox) / getSurfaceArea(parentBox) * numLeftObjects
             + getSurfaceArea(rightBox) / getSurfaceArea(parentBox) * numRightObjects;
    }

    float getSurfaceArea(AABB bbox)
    {
        float width = bbox.pmax.x - bbox.pmin.x;
        float height = bbox.pmax.y - bbox.pmin.y;
        float depth = bbox.pmax.z - bbox.pmin.z;
        return 2.0f * (width * height + width * depth + height * depth);
    }
}

