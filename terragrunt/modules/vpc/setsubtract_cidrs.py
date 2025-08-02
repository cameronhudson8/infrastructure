import ipaddress
import json
import sys

# Confirm that no command line arguments were provided, since the
# Terraform external data source provides its argument via stdin.
if len(sys.argv) > 1:
    raise ValueError(f"No command line arguments are expected. Arguments should be provided via stdin. Received these command line arguments: {json.dumps(sys.argv[1:])}")
input_args = json.loads(sys.stdin.read().strip())
ip_version = input_args.get('ipVersion')
cidr_set_a = json.loads(input_args.get('cidrSetA'))
cidr_set_b = json.loads(input_args.get('cidrSetB'))

# Validation
if not ip_version or ip_version not in ['IPV4', 'IPV6']:
    raise ValueError("JSON must contain 'ipVersion' field with value 'IPV4' or 'IPV6'")
if not cidr_set_a:
    raise ValueError("JSON must contain 'cidrSetA' field")
if not cidr_set_b:
    raise ValueError("JSON must contain 'cidrSetB' field")

# Convert to network objects
networks_a = [ipaddress.ip_network(cidr) for cidr in cidr_set_a]
networks_b = [ipaddress.ip_network(cidr) for cidr in cidr_set_b]

result_networks = []

for net_a in networks_a:
    # Start with all networks from set A
    current_networks = [net_a]

    # For each network in set B, subtract it from current networks
    for net_b in networks_b:
        new_networks = []
        for current_net in current_networks:

            # Check if net_b overlaps with current_net
            if current_net.overlaps(net_b):

                # If net_b completely contains current_net, exclude it
                if net_b.supernet_of(current_net) or net_b == current_net:
                    continue

                # If current_net completely contains net_b, split current_net
                elif current_net.supernet_of(net_b):

                    # Split current_net around net_b
                    for subnet in current_net.address_exclude(net_b):
                        new_networks.append(subnet)
                else:
                    # Partial overlap - keep the non-overlapping part
                    new_networks.append(current_net)
            else:
                # No overlap, keep the network
                new_networks.append(current_net)
        current_networks = new_networks

    result_networks.extend(current_networks)

# Convert back to strings and sort
result_cidrs = [str(net) for net in result_networks]
result_cidrs.sort()

# Output in required format. All values in the object must be strings.
output = {"cidrs_json": json.dumps(result_cidrs)}
print(json.dumps(output))
