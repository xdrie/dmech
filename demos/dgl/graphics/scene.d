/*
Copyright (c) 2014-2015 Timur Gafarov

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

module dgl.graphics.scene;

import std.stdio;

import dlib.core.memory;
import dlib.container.array;
import dlib.container.dict;
import dlib.image.color;

import dgl.core.interfaces;
import dgl.graphics.material;
import dgl.graphics.texture;
import dgl.graphics.lightmanager;
import dgl.graphics.entity;
import dgl.graphics.mesh;
import dgl.graphics.shader;
import dgl.asset.resman;

/*
 * Scene class stores a number of entities together with their meshes and materials.
 * Textures are stored separately, in ResourceManager, because textures may be shared between several Scenes.
 * Scene is bind to ResourceManager.
 */

class Scene: Drawable
{
    ResourceManager rm;

	DynamicArray!Entity _entities;
	DynamicArray!Mesh _meshes;
	DynamicArray!Material _materials;

	Dict!(size_t, string) entitiesByName;
	Dict!(size_t, string) meshesByName;
	Dict!(size_t, string) materialsByName;

    bool visible = true;
    bool lighted = true;

	Entity[] entities() {return _entities.data;}
	Mesh[] meshes() {return _meshes.data;}
	Material[] materials() {return _materials.data;}

	Entity entity(string name)
	{
	    if (name in entitiesByName)
		    return _entities.data[entitiesByName[name]-1];
		else
		    return null;
	}

	Mesh mesh(string name)
	{
	    if (name in meshesByName)
		    return _meshes.data[meshesByName[name]-1];
		else
		    return null;
	}

	Material material(string name)
	{
	    if (name in materialsByName)
		    return _materials.data[materialsByName[name]-1];
		else
		    return null;
	}

    this(ResourceManager rm)
    {
        this.rm = rm;
        createArrays();
    }

    protected void createArrays()
    {
	    entitiesByName = New!(Dict!(size_t, string));
	    meshesByName = New!(Dict!(size_t, string));
		materialsByName = New!(Dict!(size_t, string));
    }

    void clearArrays()
    {
        freeEntities();
        freeMeshes();
        freeMaterials();
        createArrays();
    }

    void resolveLinks()
    {
        foreach(ei, e; _entities.data)
        {
            foreach(mi, m; _materials.data)
            {
                if (e.materialId == m.id)
                {
                    e.modifier = m;
                    break;
                }
            }

            foreach(mi, m; _meshes.data)
            {
                if (e.meshId == m.id)
                {
                    e.drawable = m;
                    break;
                }
            }
        }

        foreach(mi, m; _meshes.data)
        {
            m.genFaceGroups(this);
        }
    }

    void createDynamicLights(bool debugDraw = false)
    {
        foreach(i, e; _entities.data)
        {
            if (e.type == 1)
            {
                Color4f col = e.props["color"].toColor4f;
                auto light = rm.lm.addPointLight(e.position);
                light.debugDraw = debugDraw;
                light.diffuseColor = col;
                e.drawable = light;
            }
        }
    }

    Entity addEntity(string name, Entity e)
    {
	    _entities.append(e);
        entitiesByName[name] = _entities.length;
        return e;
    }

    Mesh addMesh(string name, Mesh m)
    {
	    _meshes.append(m);
        meshesByName[name] = _meshes.length;
        return m;
    }

    Material addMaterial(string name, Material m)
    {
	    _materials.append(m);
        materialsByName[name] = _materials.length;
        return m;
    }

    Material getMaterialById(int id)
    {
        Material res = null;
        foreach(mi, mat; _materials.data)
        {
            if (mat.id == id)
            {
                res = mat;
                break;
            }
        }
        return res;
    }

    Texture getTexture(string filename)
    {
        return rm.getTexture(filename);
    }

    void freeEntities()
    {
        foreach(i, e; _entities.data)
            e.free();
        _entities.free();
		    Delete(entitiesByName);
    }

    void freeMeshes()
    {
        foreach(i, m; _meshes.data)
            m.free();
        _meshes.free();
		    Delete(meshesByName);
    }

    void freeMaterials()
    {
        foreach(i, m; _materials.data)
            m.free();
        _materials.free();
		    Delete(materialsByName);
    }

    void setMaterialsShadeless(bool shadeless)
    {
        foreach(i, m; _materials.data)
        {
            m.shadeless = shadeless;
        }
    }

    void setMaterialsUseTextures(bool mode)
    {
        foreach(i, m; _materials.data)
            m.useTextures = mode;
    }

    void setMaterialsAmbientColor(Color4f col)
    {
        foreach(i, m; _materials.data)
        {
            m.ambientColor = col;
        }
    }

    void setMaterialsSpecularColor(Color4f col)
    {
        foreach(i, m; _materials.data)
        {
            m.specularColor = col;
        }
    }

    void setMaterialsShader(Shader shader)
    {
        foreach(i, m; _materials.data)
        {
            m.shader = shader;
        }
    }

    void setMaterialsTextureSlot(uint src, uint dest)
    {
        foreach(i, m; _materials.data)
        {
            m.textures[dest] = m.textures[src];
            m.textures[src] = null;
        }
    }

    void draw(double dt)
    {
        foreach(i, e; _entities.data)
        {
            if (!lighted)
                rm.lm.lightsOn = false;
            rm.lm.bind(e, dt);
            e.draw(dt);
            if (!lighted)
                rm.lm.lightsOn = true;
            rm.lm.unbind(e);
        }
    }

    void free()
    {
        Delete(this);
    }

    ~this()
    {
        freeEntities();
        freeMeshes();
        freeMaterials();
    }
}