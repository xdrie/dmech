/*
Copyright (c) 2014 Timur Gafarov 

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

module dmech.pcm;

import dlib.math.vector;
import dmech.contact;

/*
 * Persistent contact manifold.
 * Stores information about two bodies' collision.
 * Contacts are collected incrementally
 * (for all-at-once solution see cm.d).
 *
 * TODO: use squared distance in methods
 * TODO: overflow handling
 */
struct PersistentContactManifold
{
    Contact[4] contacts;
    uint numContacts = 0;

    void addContact(Contact c)
    {
        bool farEnough = true;

        for (uint i = 0; i < numContacts; i++)
        {
            float d = distance(c.point, contacts[i].point);
            farEnough = farEnough && (d > 0.1f); //0.1f
        }

        if (farEnough)
            append(c);
    }

    void update()
    {
        for (uint i = 0; i < numContacts; )
        {
            auto c = &contacts[i];

            Vector3f p1, p2;

            if (c.body1.dynamic)
                p1 = c.shape1RelPoint + c.shape1.position;
            else
                p1 = c.shape1RelPoint + c.shape1pos;
                
            if (c.body2.dynamic)
                p2 = c.shape2RelPoint + c.shape2.position;
            else
                p2 = c.shape2RelPoint + c.shape2pos;

            float d = distance(p1, p2);

            if (d > 0.15f) //0.14f
            {
                this.removeContact(i);
            }
            else
            {
                c.point = (p1 + p2) * 0.5f;
                i++;
            }
        }
    }

    void append(Contact c)
    {
        if (numContacts < contacts.length)
        {
            contacts[numContacts] = c;
            numContacts++;
        }
    }

    void removeContact(uint n)
    {
        uint i = 0;
        for (uint j = 0; j < n; j++)
        {
            if (j != n)
                contacts[i++] = contacts[j];
        }
        numContacts--;
    }
}

