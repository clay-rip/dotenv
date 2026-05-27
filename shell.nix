{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
	packages = [ pkgs.mise ];

	shellHook = ''
		eval "$(mise activate bash)"
		mise install
	'';
}
