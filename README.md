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
  sum () {
      bc <<< "$1 + $2"
  }

  test_sum_int () {
      assert_stdout 'sum 1 2' - <<< 3
  }

  test_sum_float () {
      assert_stdout 'sum 0.9 2.1' - <<< '3.0'
  }

  test_sum_invalid () {
      assert_fail 'sum'
  }

  set -u
  shelter_run_test_class sum test_sum_
  ```


## Highlights

- Machine-readable output (JUnit XML output format coming soon!)
- STDOUT and STDERR are captured
- Test case, class, suite support
- Detailed documentation (`man shelter.sh`)


## Showcase

```bash
foo () {
    assert_success true
}

bar () {
    assert_fail false
}

test_hello () {
    assert_stdout 'echo Hello' - <<< 'Hello'
}

test_world () {
    echo World >./tempfile
    assert_stdout 'echo World' ./tempfile
}

suite_1 () {
    shelter_run_test_case foo
    shelter_run_test_case bar
    shelter_rn_test_class PrefixedTests test_
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
