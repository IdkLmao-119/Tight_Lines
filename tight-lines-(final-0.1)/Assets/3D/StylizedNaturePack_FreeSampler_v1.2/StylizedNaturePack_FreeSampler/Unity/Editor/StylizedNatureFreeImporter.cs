// Stylized Nature FREE Sampler - automatic import setup for Unity.
// Safe to keep next to the Pack 1 importer (different namespace; running both is harmless).
// Keep this file inside a folder named "Editor". It runs whenever a model of the
// pack (any FBX whose path contains "StylizedNaturePack") is imported:
//   * meshes named UCX_* become convex MeshColliders (their renderer is removed)
//   * models with physics = "dynamic" get a Rigidbody with the mass stored in the FBX
//   * the _LOD0/_LOD1 meshes become a LOD Group (Unity does this from the names)
// If you add this script after the models, right-click the FBX folder > Reimport.
#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;

namespace StylizedNatureFree
{
    public class StylizedNatureFreeImporter : AssetPostprocessor
    {
        bool IsPackAsset => assetPath.Replace('\\', '/').Contains("StylizedNaturePack");

        void OnPostprocessGameObjectWithUserProperties(GameObject go, string[] names, object[] values)
        {
            if (!IsPackAsset) return;
            string physics = null;
            float mass = 1f;
            for (int i = 0; i < names.Length; i++)
            {
                if (names[i] == "physics") physics = values[i] as string;
                else if (names[i] == "mass") mass = System.Convert.ToSingle(values[i]);
            }
            if (physics == "dynamic" && go.GetComponent<Rigidbody>() == null)
            {
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = Mathf.Max(mass, 0.1f);
                rb.interpolation = RigidbodyInterpolation.Interpolate;
                rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            }
        }

        void OnPostprocessModel(GameObject root)
        {
            if (!IsPackAsset) return;
            foreach (var mf in root.GetComponentsInChildren<MeshFilter>(true))
            {
                if (!mf.name.StartsWith("UCX_")) continue;
                var go = mf.gameObject;
                var collider = go.AddComponent<MeshCollider>();
                collider.sharedMesh = mf.sharedMesh;
                collider.convex = true;
                var mr = go.GetComponent<MeshRenderer>();
                if (mr != null) Object.DestroyImmediate(mr);
                Object.DestroyImmediate(mf);
            }
        }
    }
}
#endif
