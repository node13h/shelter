# shelter - Shell-based testing framework


## What is it useful for?

- Writing your system compliance and acceptance tests in pure Bash. An alternative to ServerSpec/Inspec.

  ```bash
  test_service_sshd () {
      assert_success 'systemctl is-active sshd'
  }

  test_service_ntpd () {
      assert_success 'systemctl is-active ntpd'
  }

  shelter_run_test_class myservices test_service_
  ```

- Writing unit-tests for your shell scripts and libraries

  ```bash
  add () {
      bc <<< "$1 + $2"
  }

  test_add_int () {
      assert_stdout 'add 1 2' <<< 3
  }

  test_add_float () {
      assert_stdout 'add 0.9 2.1' <<< '3.0'
  }

  test_add_invalid () {
      assert_fail 'add'
  }

  set -u
  shelter_run_test_class add test_add_
  ```


## Highlights

- Machine-readable output (JUnit XML output format coming soon!)
- Environment is captured
- STDOUT and STDERR are captured
- Test case, class, suite support
- Detailed documentation (`man shelter.sh`)


## Showcase

```bash
source shelter.sh

foo () {
    assert_success true
}

bar () {
    assert_fail false
}

test_good_hello () {
    assert_stdout 'echo Hello' <<< 'Hello'
}

test_good_world () {
    assert_stdout 'echo World' <(echo World)
}

test_bad_stdout () {
    assert_stdout 'echo TEST' <<< 'FAIL'
}

test_bad_exit () {
    assert_success false
}

suite_1 () {
    shelter_run_test_case foo
    shelter_run_test_case bar
    shelter_run_test_class SuccessfulTests test_good_
    shelter_run_test_class FailingTests test_bad_
}

shelter_run_test_suite suite_1
```


## Installing

### From source

```bash
sudo make install
```

### Packages for RedHat-based systems

```bash
cat <<"EOF" | sudo tee /etc/yum.repos.d/alikov.repo
[alikov]
name=alikov
baseurl=https://dl.bintray.com/alikov/rpm
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://bintray.com/user/downloadSubjectPublicKey?username=bintray
enabled=1
EOF

sudo yum install shelter
```

### Packages for Debian-based systems

```bash
curl 'https://bintray.com/user/downloadSubjectPublicKey?username=bintray' | sudo apt-key add -

cat <<"EOF" | sudo tee /etc/apt/sources.list.d/alikov.list
deb https://dl.bintray.com/alikov/deb xenial main
EOF

sudo apt-get update && sudo apt-get install shelter
```
