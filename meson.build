project('Photon Libary', 'd',
    meson_version : '>=0.44',
    subproject_dir : '3rd-party',
    license : 'Boost',
    version : '0.1.0'
)

version = meson.project_version()

http_parser_sp = subproject('http-parser')

http_dep = declare_dependency(
	link_with: http_parser_sp.get_variable('lib'),
	include_directories: include_directories('3rd-party/http-parser'))


subdir('src')

subdir('bench/static_http')

