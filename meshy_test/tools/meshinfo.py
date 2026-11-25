import sys, bpy, bmesh
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=sys.argv[1])
for o in bpy.context.scene.objects:
    if o.type != "MESH": continue
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    nonman = sum(1 for e in bm.edges if not e.is_manifold)
    bound = sum(1 for e in bm.edges if e.is_boundary)
    # loose parts
    seen=set(); parts=0
    for v in bm.verts:
        if v.index in seen: continue
        parts+=1; stack=[v]
        while stack:
            x=stack.pop()
            if x.index in seen: continue
            seen.add(x.index)
            stack.extend(e.other_vert(x) for e in x.link_edges)
    print(o.name, "verts", len(bm.verts), "faces", len(bm.faces), "parts", parts, "nonmanifold", nonman, "boundary", bound)
