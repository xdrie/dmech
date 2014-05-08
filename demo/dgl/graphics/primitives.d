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

module dgl.graphics.primitives;

import derelict.opengl.gl;
import derelict.opengl.glu;
import dlib.math.vector;
import dgl.graphics.gobject;

class GSphere: GraphicObject
{
    GLUquadricObj* quadric;
    uint displayList;

    this(float r)
    {
        quadric = gluNewQuadric();
        gluQuadricNormals(quadric, GLU_SMOOTH);
        gluQuadricTexture(quadric, GL_TRUE);

        displayList = glGenLists(1);
        glNewList(displayList, GL_COMPILE);
        gluSphere(quadric, r, 24, 16);
        glEndList();
    }

    override void render(double delta)
    {
        glCallList(displayList);
    }
}

class GBox: GraphicObject
{
    uint displayList;

    this(Vector3f hsize)
    {
        displayList = glGenLists(1);
        glNewList(displayList, GL_COMPILE);

        Vector3f pmax = +hsize;
        Vector3f pmin = -hsize;

        glBegin(GL_QUADS);
    
            glNormal3f(0,0,1); glVertex3f(pmin.x,pmin.y,pmax.z);
            glNormal3f(0,0,1); glVertex3f(pmax.x,pmin.y,pmax.z);
            glNormal3f(0,0,1); glVertex3f(pmax.x,pmax.y,pmax.z);
            glNormal3f(0,0,1); glVertex3f(pmin.x,pmax.y,pmax.z);

            glNormal3f(1,0,0); glVertex3f(pmax.x,pmin.y,pmax.z);
            glNormal3f(1,0,0); glVertex3f(pmax.x,pmin.y,pmin.z);
            glNormal3f(1,0,0); glVertex3f(pmax.x,pmax.y,pmin.z);
            glNormal3f(1,0,0); glVertex3f(pmax.x,pmax.y,pmax.z);

            glNormal3f(0,1,0); glVertex3f(pmin.x,pmax.y,pmax.z);
            glNormal3f(0,1,0); glVertex3f(pmax.x,pmax.y,pmax.z);
            glNormal3f(0,1,0); glVertex3f(pmax.x,pmax.y,pmin.z);
            glNormal3f(0,1,0); glVertex3f(pmin.x,pmax.y,pmin.z);

            glNormal3f(0,0,-1); glVertex3f(pmin.x,pmin.y,pmin.z);
            glNormal3f(0,0,-1); glVertex3f(pmin.x,pmax.y,pmin.z);
            glNormal3f(0,0,-1); glVertex3f(pmax.x,pmax.y,pmin.z);
            glNormal3f(0,0,-1); glVertex3f(pmax.x,pmin.y,pmin.z);

            glNormal3f(0,-1,0); glVertex3f(pmin.x,pmin.y,pmin.z);
            glNormal3f(0,-1,0); glVertex3f(pmax.x,pmin.y,pmin.z);
            glNormal3f(0,-1,0); glVertex3f(pmax.x,pmin.y,pmax.z);
            glNormal3f(0,-1,0); glVertex3f(pmin.x,pmin.y,pmax.z);

            glNormal3f(-1,0,0); glVertex3f(pmin.x,pmin.y,pmin.z);
            glNormal3f(-1,0,0); glVertex3f(pmin.x,pmin.y,pmax.z);
            glNormal3f(-1,0,0); glVertex3f(pmin.x,pmax.y,pmax.z);
            glNormal3f(-1,0,0); glVertex3f(pmin.x,pmax.y,pmin.z);
        
        glEnd();

        glEndList();
    }

    override void render(double delta)
    {
        glCallList(displayList);
    }
}

class GCylinder: GraphicObject
{
    GLUquadricObj* quadric;
    // TODO: slices, stacks
    uint displayList;
    
    this(float h, float r)
    {
        quadric = gluNewQuadric();
        gluQuadricNormals(quadric, GLU_SMOOTH);
        gluQuadricTexture(quadric, GL_TRUE);

        displayList = glGenLists(1);
        glNewList(displayList, GL_COMPILE);
        glTranslatef(0.0f, h * 0.5f, 0.0f);
        glRotatef(90.0f, 1.0f, 0.0f, 0.0f);
        gluCylinder(quadric, r, r, h, 16, 2);
        gluQuadricOrientation(quadric, GLU_INSIDE);
        gluDisk(quadric, 0, r, 16, 1);  
        gluQuadricOrientation(quadric, GLU_OUTSIDE);
        glTranslatef(0.0f, 0.0f, h);
        gluDisk(quadric, 0, r, 16, 1); 
        glEndList();
    }
    
    override void render(double delta)
    {
        glCallList(displayList);
    }
}

class GCone: GraphicObject
{
    GLUquadricObj* quadric;
    // TODO: slices, stacks
    uint displayList;
    
    this(float h, float r)
    {      
        quadric = gluNewQuadric();
        gluQuadricNormals(quadric, GLU_SMOOTH);
        gluQuadricTexture(quadric, GL_TRUE);

        displayList = glGenLists(1);
        glNewList(displayList, GL_COMPILE);
        glTranslatef(0.0f, 0.0f, -h * 0.5f);
        gluCylinder(quadric, r, 0.0f, h, 16, 2);
        gluQuadricOrientation(quadric, GLU_INSIDE);
        gluDisk(quadric, 0, r, 16, 1);
        glEndList();
    }
    
    override void render(double delta)
    {
        glCallList(displayList);
    }
}

class GEllipsoid: GraphicObject
{
    GLUquadricObj* quadric;
    uint displayList;

    Vector3f radii;
    
    this(Vector3f r)
    {
        radii = r;
  
        quadric = gluNewQuadric();
        gluQuadricNormals(quadric, GLU_SMOOTH);
        gluQuadricTexture(quadric, GL_TRUE);

        displayList = glGenLists(1);
        glNewList(displayList, GL_COMPILE);
        gluSphere(quadric, 1.0f, 24, 16);
        glEndList();
    }
    
    override void render(double delta)
    {
        glPushMatrix();
        glScalef(radii.x, radii.y, radii.z);
        glCallList(displayList);
        glPopMatrix();
    }
}

class GTriangle: GraphicObject
{
    Vector3f[3] v;
    uint displayList;
    
    this(Vector3f a, Vector3f b, Vector3f c)
    {
        v[0] = a;
        v[1] = b;
        v[2] = c;

        displayList = glGenLists(1);
        glNewList(displayList, GL_COMPILE);
        glBegin(GL_TRIANGLES);
        glVertex3fv(v[0].arrayof.ptr);
        glVertex3fv(v[1].arrayof.ptr);
        glVertex3fv(v[2].arrayof.ptr);
        glEnd();
        glEndList();
    }
    
    override void render(double delta)
    {
        glPushMatrix();
        glDisable(GL_LIGHTING);
        glDisable(GL_CULL_FACE);
        glCallList(displayList);
        glEnable(GL_CULL_FACE);
        glEnable(GL_LIGHTING);
        glPopMatrix();
    }
}
