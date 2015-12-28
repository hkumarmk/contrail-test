FROM hkumar/ubuntu-14.04.2
MAINTAINER Harish Kumar <hkumar@d4devops.org>
COPY ${CONTRAIL_INSTALL_PACKAGE:-contrail-install-packages_*~juno_all.deb} /contrail-install-packages.deb

ENV DEBIAN_FRONTEND=noninteractive

# setup contrail-install-packages
RUN dpkg -i /contrail-install-packages.deb && \
    rm -f /contrail-install-packages.deb && \
    cd /opt/contrail/contrail_packages/ && ./setup.sh && \
    apt-get install -y python-pip ant python-dev python-novaclient python-neutronclient python-cinderclient \
                    python-contrail patch python-heatclient python-ceilometerclient python-setuptools \
                    libxslt1-dev libz-dev libyaml-dev git && \
    rm -fr /opt/contrail/ && apt-get -y autoremove && apt-get -y clean
RUN git clone https://github.com/hkumarmk/contrail-test -b better_deploy /contrail-test
RUN cd /contrail-test && pip install --upgrade -r requirements.txt
COPY docker_entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["sanity"]