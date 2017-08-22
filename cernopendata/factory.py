# -*- coding: utf-8 -*-

"""cernopendata application factories."""

import os
import sys

from flaskext.markdown import Markdown

from invenio_base.app import create_app_factory
from invenio_base.wsgi import create_wsgi_factory
from invenio_config import create_conf_loader

from . import config

env_prefix = 'APP'

config_loader = create_conf_loader(config=config, env_prefix=env_prefix)

instance_path = os.getenv(env_prefix + '_INSTANCE_PATH') or \
    os.path.join(sys.prefix, 'var', 'cernopendata-instance')
"""Instance path for Invenio.

Defaults to ``<env_prefix>_INSTANCE_PATH`` or if environment variable is not
set ``<sys.prefix>/var/<app_name>-instance``.
"""

static_folder = os.getenv(env_prefix + '_STATIC_FOLDER') or \
    os.path.join(instance_path, 'static')
"""Static folder path.

Defaults to ``<env_prefix>_STATIC_FOLDER`` or if environment variable is not
set ``<sys.prefix>/var/<app_name>-instance/static``.
"""

create_api = create_app_factory(
    'cernopendata',
    config_loader=config_loader,
    blueprint_entry_points=['invenio_base.api_blueprints'],
    extension_entry_points=['invenio_base.api_apps'],
    converter_entry_points=['invenio_base.api_converters'],
    instance_path=instance_path,
)


create_app = create_app_factory(
    'cernopendata',
    config_loader=config_loader,
    blueprint_entry_points=['invenio_base.blueprints'],
    extension_entry_points=['invenio_base.apps'],
    extensions=[Markdown],
    converter_entry_points=['invenio_base.converters'],
    wsgi_factory=create_wsgi_factory({'/api': create_api}),
    instance_path=instance_path,
    static_folder=static_folder,
)
