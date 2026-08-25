use std::env;
use std::ffi::{OsStr, OsString};
use std::os::unix::process::CommandExt;
use std::process::{Command, ExitCode};

const NERDCTL: &str = env!("NERDCTL_PATH");
const CONTAINERD_ADDRESS: &str = env!("CONTAINERD_ADDRESS");
const CONTAINERD_NAMESPACE: &str = env!("CONTAINERD_NAMESPACE");
const ALLOWED_CONTAINERS: &str = env!("ALLOWED_CONTAINERS");

fn user_for(container: &OsStr) -> Option<&'static str> {
    let container = container.to_str()?;

    ALLOWED_CONTAINERS.lines().find_map(|line| {
        let (name, user) = line.split_once('\t')?;
        (name == container).then_some(user)
    })
}

fn nerdctl_command(
    container: &OsStr,
    user: &str,
    command_and_args: impl IntoIterator<Item = OsString>,
) -> Command {
    let mut command = Command::new(NERDCTL);
    command
        .env_clear()
        .env("NERDCTL_TOML", "/dev/null")
        .arg("--address")
        .arg(CONTAINERD_ADDRESS)
        .arg("--namespace")
        .arg(CONTAINERD_NAMESPACE)
        .arg("exec")
        .arg("--user")
        .arg(user)
        .arg(container)
        .arg("--")
        .args(command_and_args);
    command
}

fn main() -> ExitCode {
    let mut args = env::args_os().skip(1);
    let Some(container) = args.next() else {
        eprintln!("exec-in-container: no container supplied");
        return ExitCode::from(2);
    };
    let Some(command) = args.next() else {
        eprintln!("exec-in-container: no command supplied");
        return ExitCode::from(2);
    };
    let Some(user) = user_for(&container) else {
        eprintln!("exec-in-container: container is not allowed");
        return ExitCode::from(1);
    };

    let error = nerdctl_command(&container, user, std::iter::once(command).chain(args)).exec();
    eprintln!(
        "exec-in-container: failed to execute nerdctl: {}",
        error.kind()
    );
    ExitCode::from(126)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStringExt;

    fn command_args(command: &Command) -> Vec<OsString> {
        command.get_args().map(OsStr::to_os_string).collect()
    }

    #[test]
    fn constructs_fixed_nerdctl_invocation() {
        let command = nerdctl_command(
            OsStr::new("openchamber"),
            "5021:5000",
            [
                OsString::from("ls"),
                OsString::from("-la"),
                OsString::from("/tmp"),
            ],
        );

        assert_eq!(command.get_program(), OsStr::new(NERDCTL));
        assert_eq!(
            command_args(&command),
            [
                "--address",
                CONTAINERD_ADDRESS,
                "--namespace",
                CONTAINERD_NAMESPACE,
                "exec",
                "--user",
                "5021:5000",
                "openchamber",
                "--",
                "ls",
                "-la",
                "/tmp",
            ]
            .map(OsString::from)
        );
        assert_eq!(
            command.get_envs().collect::<Vec<_>>(),
            [(OsStr::new("NERDCTL_TOML"), Some(OsStr::new("/dev/null")))]
        );
    }

    #[test]
    fn command_arguments_cannot_become_nerdctl_options() {
        let hostile = [
            "--privileged",
            "--user",
            "--namespace",
            "--address",
            "-sh",
            ";",
            "&&",
            "$(touch /root/pwned)",
            "`touch /root/pwned`",
            "spaces in one argument",
            "newlines\nin one argument",
        ];
        let command = nerdctl_command(
            OsStr::new("openchamber"),
            "5021:5000",
            hostile.map(OsString::from),
        );
        let args = command_args(&command);
        let separator = args.iter().position(|arg| arg == "--").unwrap();

        assert_eq!(args[separator + 1..], hostile.map(OsString::from));
    }

    #[test]
    fn preserves_non_utf8_command_arguments() {
        let non_utf8 = OsString::from_vec(vec![b'f', b'o', 0x80, b'o']);
        let command = nerdctl_command(OsStr::new("openchamber"), "5021:5000", [non_utf8.clone()]);

        assert_eq!(command_args(&command).last(), Some(&non_utf8));
    }

    #[test]
    fn only_configured_containers_have_users() {
        let (name, user) = ALLOWED_CONTAINERS
            .lines()
            .next()
            .unwrap()
            .split_once('\t')
            .unwrap();

        assert_eq!(user_for(OsStr::new(name)), Some(user));
        assert_eq!(user_for(OsStr::new("not-configured")), None);
        assert_eq!(user_for(&OsString::from_vec(vec![0x80])), None);
    }
}
