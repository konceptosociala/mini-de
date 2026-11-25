project(
  'mini-de',
  ['vala', 'c'],
  version: '0.1',
  license: 'Apache-2.0',
  meson_version: '>=1.3',
  default_options: [
    'buildtype=release',
    'b_lto=true',
    'warning_level=0',
  ],
)

vapi_dir = meson.project_source_root() / 'vapi'
add_project_arguments('--vapidir', vapi_dir, language: 'vala')

vala_compiler = meson.get_compiler('vala')
c_compiler = meson.get_compiler('c')

glib = [
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
]
gio = dependency('gio-2.0')
gtk = [
  dependency('gtk+-3.0'),
  dependency('gdk-x11-3.0'),
  dependency('gio-unix-2.0'),
]
# as plain C libraries: for dependency() Meson would ask Vala for bindings with the same names
x11 = [
  c_compiler.find_library('X11'),
  c_compiler.find_library('Xinerama'),
]
posix = vala_compiler.find_library('posix')
xl = vala_compiler.find_library('xl', dirs: vapi_dir)

subdir('src')
