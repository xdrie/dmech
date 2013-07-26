/*
Copyright (c) 2013 Timur Gafarov 

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

module dmech.world;

import std.stdio;

import dlib.math.vector;

import dlib.geometry.triangle;
import dlib.geometry.sphere;

import dmech.bvh;
import dmech.geometry;
import dmech.rigidbody;
import dmech.collision;
import dmech.mpr;
import dmech.contact;
import dmech.solver;

class PhysicsWorld
{
    RigidBody[] bodies;
    Vector3f gravity = Vector3f(0.0f, -9.81f, 0.0f);

    // temporary triangle object to deal with BVH data
    RigidBody tmpTri;
    GeomTriangle tmpTriGeom;
    BVHNode bvhRoot = null;
    
    this()
    {
        tmpTri = new RigidBody();
        tmpTri.type = BodyType.Static;
        tmpTriGeom = new GeomTriangle(
            Vector3f(-1.0f, 0.0f, -1.0f), 
            Vector3f(+1.0f, 0.0f,  0.0f),
            Vector3f(-1.0f, 0.0f, +1.0f));
        tmpTri.setGeometry(tmpTriGeom);
        tmpTri.setMass(1000000.0f); // Virtually infinite mass
    }
    
    RigidBody addDynamicBody(Vector3f pos, float mass)
    {
        auto b = new RigidBody(pos);
        b.setMass(mass);
        b.type = BodyType.Dynamic;
        bodies ~= b;
        return b;
    }
    
    RigidBody addStaticBody(Vector3f pos)
    {
        auto b = new RigidBody(pos);
        b.setMass(1000000.0f);
        b.type = BodyType.Static;
        bodies ~= b;
        return b;
    }
    
    void update(double delta)
    {
        // Apply gravity to dynamic bodies
        Vector3f dtgrav = gravity;
        foreach(b; bodies)
        if (b.type == BodyType.Dynamic)
        {
            if (!b.disableGravity)
                b.applyForce(b.mass * dtgrav);
            b.onGround = false;
        }
        
        simulationStep(delta);
    }
    
    void simulationStep(double delta)
    {       
        if (bodies.length == 0)
            return;
        
        enum iterations = 10;
        delta /= iterations;
        
        for(uint iteration = 0; iteration < iterations; iteration++)
        {
            // Integrate velocities and positions
            foreach(b; bodies)
            {
                b.integrate(delta);
                b.updateGeomTransformation();
            }

            // Find and resolve collisions between bodies
            for (int i = 0; i < bodies.length - 1; i++)   
            for (int j = i + 1; j < bodies.length; j++)
            {
                Contact c;
                if (checkCollision(bodies[i], bodies[j], c))
                {
                    solveContact(c, iterations);
                    correctPositions(c);

                    Vector3f dirToContact = (c.point - bodies[i].position).normalized;
                    float groundness = dot(gravity.normalized, dirToContact);
                    if (groundness > 0.7f)
                        bodies[i].onGround = true;

                    dirToContact = (c.point - bodies[j].position).normalized;
                    groundness = dot(gravity.normalized, dirToContact);
                    if (groundness > 0.7f)
                        bodies[j].onGround = true;
                }
            }

            // Find and resolve collisions between dynamic bodies 
            // and BVH (static triangle mesh)
            if (bvhRoot !is null)
            foreach(rb; bodies)
            {
                // There may be more than one contact at a time
                static Contact[5] contacts;
                static Triangle[5] contactTris;
                uint numContacts = 0;
                
                Sphere sphere;
                
                if (rb.type == BodyType.Dynamic)
                {
                    Contact c;
                    c.body1 = rb;
                    c.body2 = tmpTri;
                    c.fact = false;

                    sphere = rb.geometry.boundingSphere;

                    bvhRoot.traverseBySphere(sphere, (ref Triangle tri)
                    {
                        // Update temporary triangle to check collision
                        tmpTriGeom.transformation.translation = tri.barycenter;
                        tmpTriGeom.v[0] = tri.v[0] - tri.barycenter;
                        tmpTriGeom.v[1] = tri.v[1] - tri.barycenter;
                        tmpTriGeom.v[2] = tri.v[2] - tri.barycenter;

                        bool collided = MPRCollisionTest(rb.geometry, tmpTriGeom, c);
                
                        if (collided)
                        {                
                            if (numContacts < contacts.length)
                            {
                                contacts[numContacts] = c;
                                contactTris[numContacts] = tri;
                                numContacts++;
                            }
                        }
                    });
                }

               /*
                * NOTE:
                * There is a problem when rolling bodies over a triangle mesh. Instead of rolling 
                * straight it will get influenced when hitting triangle edges. 
                * Current solution is to solve only the contact with deepest penetration and 
                * throw out all others. Another possible approach is to merge all contacts that 
                * are within epsilon of each other. When merging the contacts, average and 
                * re-normalize the normals, and average the penetration depth value.
                */

                int deepestContactIdx = -1;
                float maxPen = 0.0f;
                float bestGroundness = -1.0f;
                foreach(i; 0..numContacts)
                {
                    if (contacts[i].penetration > maxPen)
                    {
                        deepestContactIdx = i;
                        maxPen = contacts[i].penetration;
                    }
                    
                    Vector3f dirToContact = (contacts[i].point - rb.position).normalized;
                    float groundness = dot(gravity.normalized, dirToContact);

                    if (groundness > 0.7f)
                        rb.onGround = true;
                }
 
                if (deepestContactIdx >= 0)
                {
                    auto tri = contactTris[deepestContactIdx];
                    tmpTri.position = tri.barycenter;

                    correctPositions(contacts[deepestContactIdx]);
                    solveContact(contacts[deepestContactIdx], iterations);
                }
            }
        }
        
        foreach(b; bodies)
            b.resetForces();
    }
}

