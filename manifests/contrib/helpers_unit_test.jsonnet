local kube = (import '../vendor/github.com/bitnami-labs/kube-libsonnet/kube.libsonnet');
local helpers = (import 'helpers.jsonnet');

local obj_val = {
  a: { b: { c: { field: 'value' }, b1: 'B1' } },
};
local obj_map = {
  a: { b: { c: { field: { foo: 'bar', qqq: 'xxx' } } } },
};
local obj_rfc5789_x = { a: 'b', c: { d: 'e', f: 'g' } };
local obj_rfc5789_y = { a: 'z', c: { f: null } };

// Simple use
local do_test = (
  std.assertEqual(
    { x: { y: { z: 42 } } },
    helpers.setAtPath('x.y.z', 42)
  ) &&
  // Use it to override a field
  std.assertEqual(
    obj_val { a+: { b+: { c+: { field: 'X' } } } },
    obj_val + helpers.setAtPath('a.b.c.field', 'X')
  ) &&
  // Merge at child field.foo via value
  std.assertEqual(
    obj_map { a+: { b+: { c+: { field+: { foo: 'baz' } } } } },
    helpers.mergeAtPath(obj_map, 'a.b.c.field.foo', 'baz')
  ) &&
  // Merge at parent: via map
  std.assertEqual(
    obj_map { a+: { b+: { c+: { field+: { foo: 'baz' } } } } },
    helpers.mergeAtPath(obj_map, 'a.b.c.field', { foo: 'baz' })
  ) &&
  // Merge RFC5789 example
  std.assertEqual(
    std.mergePatch(obj_rfc5789_x, obj_rfc5789_y),
    helpers.mergeAtPath(
      // Changing the value of "a" ...
      helpers.mergeAtPath(obj_rfc5789_x, 'a', 'z'),
      // ... and removing "f"
      'c.f',
      null
    )
  )
);

// A convenient valid nil Kubernetes object
kube.List() {
  metadata: { annotation: { test: do_test } },
}
