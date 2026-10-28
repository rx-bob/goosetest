// URI authority syntax for Host and request targets; no DNS lookup or native parsing.
namespace silly;

fn valid_host(value: u8[:]) -> bool {
    if value.len == 0 {
        return false;
    }
    if value[0] == '[' {
        return valid_literal_host(value);
    }
    var end = value.len;
    for index in value.len {
        if value[index] == ':' {
            end = index;
            if !valid_host_port(value[index + 1..]) {
                return false;
            }
            break;
        }
    }
    return valid_reg_name(value[..end]);
}

fn valid_literal_host(value: u8[:]) -> bool {
    var end = -1;
    for index in value.len {
        if value[index] == ']' {
            end = index;
            break;
        }
    }
    if end < 2 {
        return false;
    }
    if end + 1 < value.len {
        if value[end + 1] != ':' || !valid_host_port(value[end + 2..]) {
            return false;
        }
    }
    let literal = value[1..end];
    if literal[0] == 'v' || literal[0] == 'V' {
        return valid_ipv_future(literal);
    }
    return valid_ipv_six(literal);
}

fn valid_host_port(port: u8[:]) -> bool {
    if port.len == 0 {
        return false;
    }
    var number: i64 = 0;
    for byte in port {
        if byte < '0' || byte > '9' {
            return false;
        }
        let digit: i64 = byte - '0';
        if number > (65535 - digit) / 10 {
            return false;
        }
        number = number * 10 + digit;
    }
    return true;
}

fn valid_reg_name(name: u8[:]) -> bool {
    if name.len == 0 {
        return false;
    }
    var index = 0;
    while index < name.len {
        let byte = name[index];
        if byte == '%' {
            if name.len - index < 3 || !host_hex(name[index + 1]) || !host_hex(name[index + 2]) {
                return false;
            }
            index += 3;
        } else {
            if !host_name_byte(byte) {
                return false;
            }
            index += 1;
        }
    }
    return true;
}

fn host_name_byte(byte: u8) -> bool {
    if (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || (byte >= '0' && byte <= '9') {
        return true;
    }
    for allowed in "-._~!$&'()*+;=" {
        if byte == allowed {
            return true;
        }
    }
    return false;
}

fn host_hex(byte: u8) -> bool {
    return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f') || (byte >= 'A' && byte <= 'F');
}

fn valid_ipv_future(value: u8[:]) -> bool {
    var dot = 1;
    while dot < value.len && host_hex(value[dot]) {
        dot += 1;
    }
    if dot == 1 || dot >= value.len || value[dot] != '.' || dot + 1 == value.len {
        return false;
    }
    for byte in value[dot + 1..] {
        if !host_name_byte(byte) && byte != ':' {
            return false;
        }
    }
    return true;
}

fn valid_ipv_six(value: u8[:]) -> bool {
    var index = 0;
    var groups = 0;
    var compressed = false;
    if value.len >= 2 && value[0] == ':' && value[1] == ':' {
        compressed = true;
        index = 2;
    }
    while index < value.len {
        let start = index;
        while index < value.len && value[index] != ':' {
            index += 1;
        }
        let group = value[start..index];
        if group.len == 0 {
            return false;
        }
        if ipv_four_candidate(group) {
            if index != value.len || !valid_ipv_four(group) {
                return false;
            }
            groups += 2;
        } else {
            if group.len > 4 {
                return false;
            }
            for byte in group {
                if !host_hex(byte) {
                    return false;
                }
            }
            groups += 1;
        }
        if groups > 8 {
            return false;
        }
        if index < value.len {
            index += 1;
            if index < value.len && value[index] == ':' {
                if compressed {
                    return false;
                }
                compressed = true;
                index += 1;
            } else if index == value.len {
                return false;
            }
        }
    }
    return if compressed {
        groups < 8
    } else {
        groups == 8
    };
}

fn ipv_four_candidate(value: u8[:]) -> bool {
    for byte in value {
        if byte == '.' {
            return true;
        }
    }
    return false;
}

fn valid_ipv_four(value: u8[:]) -> bool {
    var start = 0;
    var groups = 0;
    for end in value.len + 1 {
        if end < value.len && value[end] != '.' {
            continue;
        }
        let group = value[start..end];
        if group.len == 0 || group.len > 3 || (group.len > 1 && group[0] == '0') {
            return false;
        }
        var number = 0;
        for byte in group {
            if byte < '0' || byte > '9' {
                return false;
            }
            number = number * 10 + byte - '0';
        }
        if number > 255 {
            return false;
        }
        groups += 1;
        start = end + 1;
    }
    return groups == 4;
}
