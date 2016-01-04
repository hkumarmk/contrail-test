from setuptools import setup, find_packages

with open('requirements.txt', 'r') as fp:
    requirements = [x.strip() for x in fp]

setup(
    name='contrail-test',
    version='2.11',
    long_description=__doc__,
    packages=find_packages(),
    include_package_data=True,
    zip_safe=False,
    install_requires=requirements,
    tests_require=['mock', 'nose'],
    test_suite='nose.collector',
    scripts=['contrail-test/run_tests.sh'],
)
