/*
Copyright (c) 2013-2014 Timur Gafarov 

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

import std.math;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.affine;
import dlib.geometry.triangle;
import dlib.geometry.sphere;

import dmech.rigidbody;
import dmech.geometry;
import dmech.shape;
import dmech.contact;
import dmech.solver;
import dmech.pairhashtable;
import dmech.collision;
import dmech.pcm;
import dmech.constraint;
import dmech.bvh;
import dmech.mpr;

/*
 * World object stores bodies and constraints and performs
 * simulation cycles on them.
 */

class World
{
    RigidBody[] staticBodies;
    RigidBody[] dynamicBodies;
    Constraint[] constraints;

    Vector3f gravity;
    
    protected uint maxShapeId = 1;

    PairHashTable!PersistentContactManifold manifolds;

    bool broadphase = false;
    bool warmstart = false;

    //uint solverIterations = 0;
    uint positionCorrectionIterations = 10;
    uint constraintIterations = 20;
    
    BVHNode!Triangle bvhRoot = null;

    // Proxy triangle to deal with BVH data
    RigidBody proxyTri;
    ShapeComponent proxyTriShape;
    GeomTriangle proxyTriGeom;

    this(size_t maxCollisions = 1000)
    {
        gravity = Vector3f(0.0f, -9.80665f, 0.0f); // Earth

        manifolds = new PairHashTable!PersistentContactManifold(maxCollisions);
        
        // Create proxy triangle 
        proxyTri = new RigidBody();
        proxyTri.position = Vector3f(0, 0, 0);
        proxyTriGeom = new GeomTriangle(
            Vector3f(-1.0f, 0.0f, -1.0f), 
            Vector3f(+1.0f, 0.0f,  0.0f),
            Vector3f(-1.0f, 0.0f, +1.0f));
        proxyTriShape = new ShapeComponent(proxyTriGeom, Vector3f(0, 0, 0), 1);
        proxyTriShape.id = maxShapeId;
        maxShapeId++;
        proxyTriShape.transformation = 
            proxyTri.transformation() * translationMatrix(proxyTriShape.centroid);
        proxyTri.shapes ~= proxyTriShape;
        proxyTri.mass = float.infinity;
        proxyTri.invMass = 0.0f;
        proxyTri.inertiaTensor = matrixf(
            float.infinity, 0, 0,
            0, float.infinity, 0,
            0, 0, float.infinity
        );
        proxyTri.invInertiaTensor = matrixf(
            0, 0, 0,
            0, 0, 0,
            0, 0, 0
        );
        proxyTri.dynamic = false;
    }

    RigidBody addDynamicBody(Vector3f pos, float mass = 0.0f)
    {
        auto b = new RigidBody();
        b.position = pos;
        b.mass = mass;
        b.invMass = 1.0f / mass;
        b.inertiaTensor = matrixf(
            mass, 0, 0,
            0, mass, 0,
            0, 0, mass
        );
        b.invInertiaTensor = matrixf(
            0, 0, 0,
            0, 0, 0,
            0, 0, 0
        );
        b.dynamic = true;
        dynamicBodies ~= b;
        return b;
    }

    RigidBody addStaticBody(Vector3f pos)
    {
        auto b = new RigidBody();
        b.position = pos;
        b.mass = float.infinity;
        b.invMass = 0.0f;
        b.inertiaTensor = matrixf(
            float.infinity, 0, 0,
            0, float.infinity, 0,
            0, 0, float.infinity
        );
        b.invInertiaTensor = matrixf(
            0, 0, 0,
            0, 0, 0,
            0, 0, 0
        );
        b.dynamic = false;
        staticBodies ~= b;
        return b;
    }

    ShapeComponent addShapeComponent(RigidBody b, Geometry geom, Vector3f position, float mass)
    {
        auto shape = new ShapeComponent(geom, position, mass);
        shape.id = maxShapeId;
        maxShapeId++;
        b.addShapeComponent(shape);
        return shape;
    }

    Constraint addConstraint(Constraint c)
    {
        constraints ~= c;
        return c;
    }

    void update(double dt)
    {
        if (dynamicBodies.length == 0)
            return;

        foreach(ref m; manifolds)
        {
            m.update();
        }

        foreach(b; dynamicBodies)
        {
            b.updateInertia();
            b.applyForce(gravity * b.mass);
            b.integrateForces(dt);
            b.resetForces();
        }

        if (broadphase)
            findDynamicCollisionsBroadphase();
        else
            findDynamicCollisionsBruteForce();

        findStaticCollisionsBruteForce();

        solveConstraints(dt);

        foreach(b; dynamicBodies)
        {
            b.integrateVelocities(dt);
        }

        foreach(iteration; 0..positionCorrectionIterations)
        foreach(ref m; manifolds)
        foreach(i; 0..m.numContacts)
        {
            auto c = &m.contacts[i];
            solvePositionError(c, m.numContacts);
        }

        foreach(b; dynamicBodies)
        {
            b.integratePseudoVelocities(dt);
            b.updateShapeComponents();
        }
    }

    void findDynamicCollisionsBruteForce()
    {
        for (int i = 0; i < dynamicBodies.length - 1; i++)   
        {
            auto body1 = dynamicBodies[i];
            foreach(shape1; body1.shapes)
            {
                for (int j = i + 1; j < dynamicBodies.length; j++)
                {
                    auto body2 = dynamicBodies[j];
                    foreach(shape2; body2.shapes)
                    {
                        Contact c;
                        c.body1 = body1;
                        c.body2 = body2;
                        checkCollisionPair(shape1, shape2, c);
                    }
                }
            }
        }
    }

    void findDynamicCollisionsBroadphase()
    {
        for (int i = 0; i < dynamicBodies.length - 1; i++)   
        {
            auto body1 = dynamicBodies[i];
            foreach(shape1; body1.shapes)
            {
                for (int j = i + 1; j < dynamicBodies.length; j++)
                {
                    auto body2 = dynamicBodies[j];
                    foreach(shape2; body2.shapes)
                    if (shape1.boundingBox.intersectsAABB(shape2.boundingBox))
                    {
                        Contact c;
                        c.body1 = body1;
                        c.body2 = body2;
                        checkCollisionPair(shape1, shape2, c);
                    }
                }
            }
        }
    }

    void findStaticCollisionsBruteForce()
    {
        foreach(body1; dynamicBodies)
        {
            foreach(shape1; body1.shapes)
            {
                foreach(body2; staticBodies)
                {
                    foreach(shape2; body2.shapes)
                    {
                        Contact c;
                        c.body1 = body1;
                        c.body2 = body2;
                        c.shape2pos = shape2.position;
                        checkCollisionPair(shape1, shape2, c);
                    }
                }
            }
        }
        
        // Find collisions between dynamic bodies 
        // and the BVH world (static triangle mesh)
        if (bvhRoot !is null)
        foreach(rb; dynamicBodies)
        foreach(shape; rb.shapes)
        {
            // There may be more than one contact at a time
            static Contact[5] contacts;
            static Triangle[5] contactTris;
            uint numContacts = 0;

            Contact c;
            c.body1 = rb;
            c.body2 = proxyTri;
            c.fact = false;

            Sphere sphere = shape.boundingSphere;

            bvhRoot.traverseBySphere(sphere, (ref Triangle tri)
            {
                // Update temporary triangle to check collision
                proxyTriShape.transformation = translationMatrix(tri.barycenter);
                proxyTriGeom.v[0] = tri.v[0] - tri.barycenter;
                proxyTriGeom.v[1] = tri.v[1] - tri.barycenter;
                proxyTriGeom.v[2] = tri.v[2] - tri.barycenter;

                bool collided = checkCollision(shape, proxyTriShape, c);
                
                if (collided)
                {                
                    if (numContacts < contacts.length)
                    {
                        c.shape1RelPoint = c.point - shape.position;
                        c.shape2RelPoint = c.point - tri.barycenter;
                        c.body1RelPoint = c.point - c.body1.worldCenterOfMass;
                        c.body2RelPoint = c.point - tri.barycenter;
                        c.shape1 = shape;
                        c.shape2 = proxyTriShape;
                        c.shape2pos = tri.barycenter;
                        contacts[numContacts] = c;
                        contactTris[numContacts] = tri;
                        numContacts++;
                    }
                }
            });
            
           /*
            * NOTE:
            * There is a problem when rolling bodies over a triangle mesh. Instead of rolling 
            * straight it will get influenced when hitting triangle edges. 
            * Current solution is to solve only the contact with deepest penetration and 
            * throw out all others. Other possible approach is to merge all contacts that 
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
                
                //Vector3f dirToContact = (contacts[i].point - rb.position).normalized;
                //float groundness = dot(gravity.normalized, dirToContact);
                //if (groundness > 0.7f)
                //    rb.onGround = true;
            }
                
            if (deepestContactIdx >= 0)
            {                   
                auto co = &contacts[deepestContactIdx];    
                co.calcFDir();
                    
                auto m = manifolds.get(shape.id, proxyTriShape.id);
                if (m is null)
                {
                    PersistentContactManifold m1;
                    m1.addContact(*co);
                    manifolds.set(shape.id, proxyTriShape.id, m1);
                }
                else
                {
                    m.addContact(*co);
                }
            }
            else
                manifolds.remove(shape.id, proxyTriShape.id);
        }
    }

    void checkCollisionPair(ShapeComponent shape1, ShapeComponent shape2, ref Contact c)
    {
        if (checkCollision(shape1, shape2, c))
        {
            c.body1RelPoint = c.point - c.body1.worldCenterOfMass;
            c.body2RelPoint = c.point - c.body2.worldCenterOfMass;
            c.shape1RelPoint = c.point - shape1.position;
            c.shape2RelPoint = c.point - shape2.position;
            c.shape1 = shape1;
            c.shape2 = shape2;
            c.calcFDir();

            auto m = manifolds.get(shape1.id, shape2.id);
            if (m is null)
            {
                PersistentContactManifold m1;
                m1.addContact(c);
                manifolds.set(shape1.id, shape2.id, m1);
            }
            else
            {
                m.addContact(c);
            }
        }
        else
        {
            manifolds.remove(shape1.id, shape2.id);
        }
    }

    void solveConstraints(double dt)
    {
        foreach(ref m; manifolds)
        foreach(i; 0..m.numContacts)
        {
            auto c = &m.contacts[i];
            prepareContact(c);
        }

        foreach(c; constraints)
        {
            c.prepare(dt);
        }

        foreach(iteration; 0..constraintIterations)
        {
            foreach(c; constraints)
                c.step();

            foreach(ref m; manifolds)
            foreach(i; 0..m.numContacts)
            {
                auto c = &m.contacts[i];
                solveContact(c, dt);
            }
        }
    }
}

