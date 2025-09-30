FROM ubuntu:24.04

RUN apt-get update && apt-get install -y python3 python3-pip

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cron \
    curl \
    dnsutils \
    git \
    vim \
    bash \
    #redis \
    supervisor \
    python3.12-venv \
    ssh

RUN apt-get install -y apache2 --no-install-recommends ; apt-get install -y libapache2-mod-wsgi-py3 --no-install-recommends
RUN a2enmod wsgi
RUN rm -rf /etc/apache2/sites-available/000-default.conf
RUN rm -rf /etc/apache2/sites-enabled/000-default.conf


# Copy SSH private key for app_one
COPY ./secrets/id_rsa_app_one /run/secrets/id_rsa_app

# Copy SSH config file
COPY ./ssh/ssh_config /etc/ssh/ssh_config

# Set working directory
WORKDIR /app

COPY ./requirements.txt /app
#COPY ./app/wsgi.ini /app/wsgi.ini
#COPY ./app/wsgi.py /app/wsgi.py
COPY ./app/FlaskApp.wsgi /app/FlaskApp.wsgi
COPY ./app/src/app.py /app/src/app.py
COPY ./app/src/static/ /app/src/static/
COPY ./usr/local/bin/ /usr/local/bin/
COPY ./rootfs/etc/supervisord.conf/ /etc/supervisor/supervisord.conf
COPY ./rootfs/etc/entrypoint.d/ /etc/entrypoint.d/
COPY ./rootfs/etc/supervisor.d/ /etc/supervisor.d/


RUN python3 -m venv /venv
ENV PATH="/venv/bin:$PATH"
RUN /venv/bin/pip install --upgrade pip
RUN pip install -r /app/requirements.txt


RUN chown -R www-data:www-data /app
COPY ./FlaskApp.conf /etc/apache2/sites-available/FlaskApp.conf


# Set Root to bash not ash and overwrite .bashrc
RUN set -ex \
    && sed -i 's/root:\/bin\/ash/root:\/bin\/bash/' /etc/passwd \
    && cp /etc/skel/.bashrc /root/.bashrc \
    && chmod 4755 /usr/bin/crontab \
    && chmod 4755 /var/spool/cron/crontabs \
    && mkdir -p /var/log/supervisord \
    && mkdir -p /var/run/sshd \
    && chmod -R +x /usr/local/bin \
    && echo "ServerName localhost" >> /etc/apache2/apache2.conf


RUN a2ensite FlaskApp
RUN apache2ctl restart
RUN sleep 3

# Setup environment
ENV SHELL="/bin/bash" \
EDITOR="/usr/bin/vim" 





# Set permissions for the SSH key and config
RUN chmod 600 /run/secrets/id_rsa_app && chmod 644 /etc/ssh/ssh_config

# Copy the rest of the application
#COPY . .

# Set environment variables
ENV PYTHONUNBUFFERED=1

EXPOSE 5000
VOLUME ["/app/src"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
#CMD ["uwsgi", "--ini", "/app/wsgi.ini"]
