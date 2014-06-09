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

module dmech.constraint;

import std.math;
import std.algorithm;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;

import dmech.rigidbody;

abstract class Constraint
{
    RigidBody body1;
    RigidBody body2;

    void prepare(double delta);
    void step();
}

/*
 * Keeps bodies at some fixed distance from each other.
 */
class DistanceConstraint: Constraint
{
    Vector3f r1, r2;
    
    float biasFactor = 0.1f;
    float softness = 0.01f;
    float distance;
    
    float effectiveMass = 0.0f;
    float accumulatedImpulse = 0.0f;
    float bias;
    float softnessOverDt;
    
    Vector3f[4] jacobian;
    
    this(
        RigidBody body1, 
        RigidBody body2,
        float dist)
    {
        this.body1 = body1;
        this.body2 = body2;
        
        distance = dist;
    }
    
    override void prepare(double delta)
    {
        r1 = Vector3f(0.0f, 0.0f, 0.0f);
        r2 = Vector3f(0.0f, 0.0f, 0.0f);

        Vector3f p1, p2, dp;
        p1 = body1.position;
        p2 = body2.position;
        dp = p2 - p1;
        
        float deltaLength = dp.length - distance;

        Vector3f n = (p2 - p1).normalized;
            
        jacobian[0] = -n;
        jacobian[1] = -cross(r1, n);
        jacobian[2] = n;
        jacobian[3] = cross(r2, n);
            
        effectiveMass = 
            body1.invMass + 
            body2.invMass +
            dot(jacobian[1] * body1.invInertiaTensor, jacobian[1]) +
            dot(jacobian[3] * body2.invInertiaTensor, jacobian[3]);
                
        softnessOverDt = softness / delta;
        effectiveMass += softnessOverDt;

        if (effectiveMass != 0)
            effectiveMass = 1.0f / effectiveMass;
                
        bias = deltaLength * biasFactor * (1.0f / delta);
            
        if (body1.dynamic)
        {
            body1.linearVelocity += jacobian[0] * accumulatedImpulse * body1.invMass;
            body1.angularVelocity += jacobian[1] * accumulatedImpulse * body1.invInertiaTensor;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += jacobian[2] * accumulatedImpulse * body2.invMass;
            body2.angularVelocity += jacobian[3] * accumulatedImpulse * body2.invInertiaTensor;
        }
    }
    
    override void step()
    {           
        float jv =
            dot(body1.linearVelocity, jacobian[0]) +
            dot(body1.angularVelocity, jacobian[1]) +
            dot(body2.linearVelocity, jacobian[2]) +
            dot(body2.angularVelocity, jacobian[3]);
            
        float softnessScalar = accumulatedImpulse * softnessOverDt;
        float lambda = -effectiveMass * (jv + bias + softnessScalar);

        accumulatedImpulse += lambda;
        
        if (body1.dynamic)
        {
            body1.linearVelocity += jacobian[0] * lambda * body1.invMass;
            body1.angularVelocity += jacobian[1] * lambda * body1.invInertiaTensor;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += jacobian[2] * lambda * body2.invMass;
            body2.angularVelocity += jacobian[3] * lambda * body2.invInertiaTensor;
        }
    }
}

/*
 * The ball-socket constraint, also known as point to point constraint, 
 * limits the translation so that the local anchor points of two rigid bodies 
 * match in world space.
 */
class BallConstraint: Constraint
{
    Vector3f localAnchor1, localAnchor2;
    Vector3f r1, r2;

    Vector3f[4] jacobian; 
   
    float accumulatedImpulse = 0.0f;
    
    float biasFactor = 0.1f;
    float softness = 0.01f; //0.05f;
    
    float softnessOverDt;
    float effectiveMass;
    float bias;

    this(RigidBody body1, RigidBody body2, Vector3f anchor1, Vector3f anchor2)
    {
        this.body1 = body1;
        this.body2 = body2;
        
        localAnchor1 = anchor1;
        localAnchor2 = anchor2;
    }
    
    override void prepare(double delta)
    {
        Vector3f r1 = body1.orientation.rotate(localAnchor1);
        Vector3f r2 = body2.orientation.rotate(localAnchor2);

        Vector3f p1, p2, dp;
        p1 = body1.position + r1;
        p2 = body2.position + r2;

        dp = p2 - p1;

        float deltaLength = dp.length;
        Vector3f n = dp.normalized;

        jacobian[0] = -n;
        jacobian[1] = -cross(r1, n);
        jacobian[2] = n;
        jacobian[3] = cross(r2, n);

        effectiveMass = 
            body1.invMass + 
            body2.invMass +
            dot(jacobian[1] * body1.invInertiaTensor, jacobian[1]) +
            dot(jacobian[3] * body2.invInertiaTensor, jacobian[3]);

        softnessOverDt = softness / delta;
        effectiveMass += softnessOverDt;
        effectiveMass = 1.0f / effectiveMass;

        bias = deltaLength * biasFactor * (1.0f / delta);

        if (body1.dynamic)
        {
            body1.linearVelocity += jacobian[0] * body1.invMass * accumulatedImpulse;
            body1.angularVelocity += jacobian[1] * body1.invInertiaTensor * accumulatedImpulse;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += jacobian[2] * body2.invMass * accumulatedImpulse;
            body2.angularVelocity += jacobian[3] * body2.invInertiaTensor * accumulatedImpulse;
        }
    }
    
    override void step()
    {
        float jv =
            dot(body1.linearVelocity, jacobian[0]) +
            dot(body1.angularVelocity, jacobian[1]) +
            dot(body2.linearVelocity, jacobian[2]) +
            dot(body2.angularVelocity, jacobian[3]);

        float softnessScalar = accumulatedImpulse * softnessOverDt;
        float lambda = -effectiveMass * (jv + bias + softnessScalar);

        accumulatedImpulse += lambda;

        if (body1.dynamic)
        {
            body1.linearVelocity += jacobian[0] * body1.invMass * lambda;
            body1.angularVelocity += jacobian[1] * body1.invInertiaTensor * lambda;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += jacobian[2] * body2.invMass * lambda;
            body2.angularVelocity += jacobian[3] * body2.invInertiaTensor * lambda;
        }
    }
}

/*
 * Constraints a point on a body to be fixed on a line
 * which is fixed on another body.
 */
class SliderConstraint: Constraint
{
    Vector3f lineNormal;

    Vector3f localAnchor1, localAnchor2;
    Vector3f r1, r2;

    Vector3f[4] jacobian; 
   
    float accumulatedImpulse = 0.0f;
    
    float biasFactor = 0.5f;
    float softness = 0.0f;
    
    float softnessOverDt;
    float effectiveMass;
    float bias;

    this(RigidBody body1, RigidBody body2, Vector3f lineStartPointBody1, Vector3f pointBody2)
    {
        this.body1 = body1;
        this.body2 = body2;
        
        localAnchor1 = lineStartPointBody1;
        localAnchor2 = pointBody2;

        lineNormal = (lineStartPointBody1 + body1.position - 
                      pointBody2 + body2.position).normalized;
    }

    override void prepare(double delta)
    {
        Vector3f r1 = body1.orientation.rotate(localAnchor1);
        Vector3f r2 = body2.orientation.rotate(localAnchor2);

        Vector3f p1, p2, dp;
        p1 = body1.position + r1;
        p2 = body2.position + r2;

        dp = p2 - p1;

        Vector3f l = body1.orientation.rotate(lineNormal);

        Vector3f t = cross((p1 - p2), l);
        if (t.lengthsqr != 0.0f)
            t.normalize();
        t = cross(t, l);

        jacobian[0] = t;
        jacobian[1] = cross((r1 + p2 - p1), t);
        jacobian[2] = -t;
        jacobian[3] = -cross(r2, t);

        effectiveMass = 
            body1.invMass + 
            body2.invMass +
            dot(jacobian[1] * body1.invInertiaTensor, jacobian[1]) +
            dot(jacobian[3] * body2.invInertiaTensor, jacobian[3]);

        softnessOverDt = softness / delta;
        effectiveMass += softnessOverDt;

        if (effectiveMass != 0)
            effectiveMass = 1.0f / effectiveMass;

        bias = -cross(l, (p2 - p1)).length * biasFactor * (1.0f / delta);

        if (body1.dynamic)
        {
            body1.linearVelocity += body1.invMass * accumulatedImpulse * jacobian[0];
            body1.angularVelocity += accumulatedImpulse * jacobian[1] * body1.invInertiaTensor;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += body2.invMass * accumulatedImpulse * jacobian[2];
            body2.angularVelocity += accumulatedImpulse * jacobian[3] * body2.invInertiaTensor;
        }
    }

    override void step()
    {
        float jv =
            dot(body1.linearVelocity, jacobian[0]) +
            dot(body1.angularVelocity, jacobian[1]) +
            dot(body2.linearVelocity, jacobian[2]) +
            dot(body2.angularVelocity, jacobian[3]);

        float softnessScalar = accumulatedImpulse * softnessOverDt;
        float lambda = -effectiveMass * (jv + bias + softnessScalar);

        accumulatedImpulse += lambda;

        if (body1.dynamic)
        {
            body1.linearVelocity += body1.invMass * lambda * jacobian[0];
            body1.angularVelocity += lambda * jacobian[1] * body1.invInertiaTensor;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += body2.invMass * lambda * jacobian[2];
            body2.angularVelocity += lambda * jacobian[3] * body2.invInertiaTensor;
        }
    }
}

/*
class AngleConstraint: Constraint
{
    Vector3f[4] jacobian; 
   
    Vector3f accumulatedImpulse = Vector3f(0, 0, 0);
    
    float biasFactor = 0.05f;
    float softness = 0.0f;
    
    float softnessOverDt;
    Matrix3x3f effectiveMass;
    Vector3f bias;

    this(RigidBody body1, RigidBody body2)
    {
        this.body1 = body1;
        this.body2 = body2;
    }

    override void prepare(double dt)
    {
        effectiveMass = body1.invInertiaTensor + body2.invInertiaTensor;

        softnessOverDt = softness / dt;

        effectiveMass.a11 += softnessOverDt;
        effectiveMass.a22 += softnessOverDt;
        effectiveMass.a33 += softnessOverDt;

        effectiveMass = effectiveMass.inverse;

        Matrix3x3f orientationDifference = Matrix3x3f.identity;
        auto rot1 = body1.orientation.toMatrix3x3;
        auto rot2 = body2.orientation.toMatrix3x3;
        Matrix3x3f q = orientationDifference * rot2.inverse * rot1;

        Vector3f axis;
        float x = q.a32 - q.a23;
        float y = q.a13 - q.a31;
        float z = q.a21 - q.a12;
        float r = sqrt(x * x + y * y + z * z);
        float t = q.a11 + q.a22 + q.a33;
        float angle = atan2(r, t - 1);
        axis = Vector3f(x, y, z) * angle;

        if (r != 0.0f) axis = axis * (1.0f / r);

        bias = axis * biasFactor * (-1.0f / dt);

        if (body1.dynamic)
            body1.angularVelocity += accumulatedImpulse * body1.invInertiaTensor;
        if (body2.dynamic)
            body2.angularVelocity += -accumulatedImpulse * body2.invInertiaTensor;

    }

    override void step()
    {
        Vector3f jv = body1.angularVelocity - body2.angularVelocity;
        Vector3f softnessVector = accumulatedImpulse * softnessOverDt;

        Vector3f lambda = -1.0f * (jv+bias+softnessVector) * effectiveMass;
        accumulatedImpulse += lambda;

        if (body1.dynamic)
            body1.angularVelocity += lambda * body1.invInertiaTensor;
        if (body2.dynamic)
            body2.angularVelocity += -lambda * body2.invInertiaTensor;
    }
}
*/

