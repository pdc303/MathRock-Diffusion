import sys
import os
import ast
import json

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
        if arg.startswith(f'{key}='):
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

    if key in obj.keys():
        retobj['found'] = True
        retobj['value'] = obj[key]
    else:
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
        if arg.startswith(f'config='):
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
        print('lu')
        print(lu)
        text_prompt_list.append(lu['value'])
        return text_prompt_list

    lu = cu_get_config_value_inner('text_prompts', dict)

    if lu['found']:
        text_prompt_list = []
        text_prompt_list.append(lu['value']['0'])
        return text_prompt_list

    return default_value

def cu_callback_display_rate():
    pass