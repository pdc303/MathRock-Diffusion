import sys
import os
import ast
import json
import random

def cu_install_packages():
    os.system('pip install imutils')

# import additional packages required by MRD.
# these packages will already be present on Colab
def cu_import_packages():
    import imutils

def cu_get_self_dir():
    self_script = os.path.abspath(__file__)
    self_dir = os.path.dirname(self_script)
    return self_dir

def cu_str_to_bool(s):
    if s.lower() == "true":
        return True
    elif s.lower() == "false":
        return False
    else:
        print(f'Invalid boolean value: {s}')

def cu_look_for_command_line_arg(key, vartype, priority_last=True):
    retobj = {}
    retobj['found'] = False

    if priority_last:
        args_list = list(reversed(sys.argv))
    else:
        args_list = sys.argv

    for arg in args_list:
        if arg.lower().startswith(f'{key.lower()}='):
            sval = arg[len(f'{key}='):]
            retobj['found'] = True
            if vartype == str:
                retobj['value'] = sval
            elif vartype == bool:
                retobj['value'] = cu_str_to_bool(sval)
            elif vartype == float:
                retobj['value'] = float(sval)
            elif vartype == int:
                retobj['value'] = int(sval)
            elif (vartype == None) or (vartype == list):
                retobj['value'] = ast.literal_eval(sval)
            else:
                print(f'Error: Unexpected vartype {vartype}')
                sys.exit(1)

    return retobj

def read_json_key_from_file(filepath, key):
    f = open(filepath, "rb")
    if f is None:
        print("Error: Failed to open JSON file " + filepath)
        exit(1)

    obj = json.load(f)

    if obj is None:
        print("Error: Failed to parse JSON file " + filepath)
        sys.exit(1)

    f.close()

    retobj = {}

    for json_key in obj.keys():
        if json_key.lower() == key.lower():
            retobj['found'] = True
            retobj['value'] = obj[json_key]
            return retobj

    retobj['found'] = False

    return retobj

def cu_look_for_config_arg(key, vartype, priority_last=True):
    lookup_info = {}
    lookup_info['found'] = False

    if priority_last:
        args_list = list(reversed(sys.argv))
    else:
        args_list = sys.argv

    for arg in args_list:
        if arg.lower().startswith(f'config='):
            spath = arg[len(f'config='):]
            lookup_info = read_json_key_from_file(spath, key)

    return lookup_info

def cu_get_config_value_inner(varname, vartype):
    lu = cu_look_for_command_line_arg(varname, vartype)

    if lu['found']:
        return lu

    lu = cu_look_for_config_arg(varname, vartype)

    if lu['found']:
        return lu

    lu = {}
    lu['found'] = False
    return lu

def cu_get_config_value(varname, vartype, default_value):
    lu = cu_get_config_value_inner(varname, vartype)

    if lu['found']:
        return lu['value']
    else:
        return default_value

def cu_get_text_prompt_list(default_value):
    lu = cu_get_config_value_inner('text_prompt', list)

    if lu['found']:
        text_prompt_list = []
        text_prompt_list.append(lu['value'])
        return text_prompt_list

    lu = cu_get_config_value_inner('text_prompts', dict)

    if lu['found']:
        text_prompt_list = []
        text_prompt_list.append(lu['value']['0'])
        return text_prompt_list

    return default_value

def get_random_line_from_file(filepath):
    try:
        f = open(filepath, "r")
    except:
        print("Error: Failed to open file: " + filepath)
        sys.exit(1)

    lines = f.readlines()
    return random.choice(lines).replace("\n", "")

default_artists_list = f'{cu_get_self_dir()}/convert/lists/artists-curated.txt'
def get_random_artist():
    artists_list = cu_get_config_value('artists_list', str, default_artists_list)
    return get_random_line_from_file(artists_list)

default_sites_list = f'{cu_get_self_dir()}/convert/lists/sites.txt'
def get_random_site():
    sites_list = cu_get_config_value('sites_list', str, default_sites_list)
    return get_random_line_from_file(sites_list)

def process_prompt_directive_artist(prompt_str):
    while '%ARTIST%' in prompt_str:
        artist = get_random_artist()
        prompt_str = prompt_str.replace('%ARTIST%', artist, 1)

    return prompt_str

def process_prompt_directive_site(prompt_str):
    while '%SITE%' in prompt_str:
        site = get_random_site()
        prompt_str = prompt_str.replace('%SITE%', site, 1)

    return prompt_str

def process_prompt_list(prompt_list):
    global n_batches

    prompt_list_out = []

    for prompt in prompt_list:
        for bn in range(n_batches):
            new_prompt = []
            for prompt_part in prompt:
                prompt_part = process_prompt_directive_artist(prompt_part)
                prompt_part = process_prompt_directive_site(prompt_part)
                new_prompt.append(prompt_part)
            prompt_list_out.append(new_prompt)

    n_batches = 1

    return prompt_list_out

def make_init_image_list():
    init_image_opt = cu_get_config_value('init_image', str, None)

    if init_image_opt:
        # default to steps / 2
        skip_steps_opt = cu_get_config_value('skip_steps', int, int(steps / 2))
        return [ [ init_image_opt, skip_steps_opt ] ]
    else:
        return []

def cu_callback_display_rate():
    pass

def cu_callback_startup():
    cu_install_packages()
    cu_import_packages()


