project('photon', 'd',
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

dlang = import('dlang')
dlang.generate_dub_file(meson.project_name().to_lower(), meson.source_root(),
                        authors: ['Dmitry Olshansky'],
                        description: 'Photon - a transparent fiber scheduler',
                        copyright: 'Copyright © 2023, Dmitry Olshansky',
                        license: 'BOOST',
                        targetType: 'library'
)

subdir('src')

subdir('bench/static_http')

subdir('tests')