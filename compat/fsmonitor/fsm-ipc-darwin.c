#include "cache.h"
#include "config.h"
#include "strbuf.h"
#include "fsmonitor.h"
#include "fsmonitor-ipc.h"
#include "fsmonitor-path-utils.h"

static GIT_PATH_FUNC(fsmonitor_ipc__get_default_path, "fsmonitor--daemon.ipc")

const char *fsmonitor_ipc__get_path(void)
{
	static const char *ipc_path;
	SHA_CTX sha1ctx;
	char *sock_dir;
	struct strbuf ipc_file = STRBUF_INIT;
	unsigned char hash[SHA_DIGEST_LENGTH];

	if (ipc_path)
		return ipc_path;

	ipc_path = fsmonitor_ipc__get_default_path();

	/* By default the socket file is created in the .git directory */
	if (fsmonitor__is_fs_remote(ipc_path) < 1)
		return ipc_path;

	SHA1_Init(&sha1ctx);
	SHA1_Update(&sha1ctx, the_repository->worktree, strlen(the_repository->worktree));
	SHA1_Final(hash, &sha1ctx);

	repo_config_get_string(the_repository, "fsmonitor.socketdir", &sock_dir);

	/* Create the socket file in either socketDir or $HOME */
	if (sock_dir && *sock_dir)
		strbuf_addf(&ipc_file, "%s/.git-fsmonitor-%s",
					sock_dir, hash_to_hex(hash));
	else
		strbuf_addf(&ipc_file, "~/.git-fsmonitor-%s", hash_to_hex(hash));

	ipc_path = interpolate_path(ipc_file.buf, 1);
	if (!ipc_path)
		die(_("Invalid path: %s"), ipc_file.buf);

	strbuf_release(&ipc_file);
	return ipc_path;
}
