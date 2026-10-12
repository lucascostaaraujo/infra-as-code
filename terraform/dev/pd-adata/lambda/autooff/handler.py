"""
Liga/desliga recursos marcados com a tag autoOnOff=true.

Disparada pelo EventBridge Scheduler (ver autooff.tf) com o payload
{"action": "start"} (07:00 BRT, seg-sex) ou {"action": "stop"} (19:00 BRT,
seg-sex). Descobre os recursos via Resource Groups Tagging API (funciona pra
qualquer servico que suporte tags), mas so sabe agir sobre EC2 e RDS -- os
unicos tipos com um estado start/stop de verdade.
"""

import boto3

TAG_KEY = "autoOnOff"
TAG_VALUE = "true"


def _find_tagged_arns():
    client = boto3.client("resourcegroupstaggingapi")
    paginator = client.get_paginator("get_resources")
    arns = []
    for page in paginator.paginate(TagFilters=[{"Key": TAG_KEY, "Values": [TAG_VALUE]}]):
        arns.extend(item["ResourceARN"] for item in page["ResourceTagMappingList"])
    return arns


def _split_by_service(arns):
    ec2_instance_ids = []
    rds_instance_ids = []
    for arn in arns:
        # arn:aws:ec2:<region>:<account>:instance/i-xxxx
        # arn:aws:rds:<region>:<account>:db:<db-identifier>
        parts = arn.split(":", 5)
        if len(parts) < 6:
            continue
        service, resource = parts[2], parts[5]
        if service == "ec2" and resource.startswith("instance/"):
            ec2_instance_ids.append(resource.split("/", 1)[1])
        elif service == "rds" and resource.startswith("db:"):
            rds_instance_ids.append(resource.split(":", 1)[1])
    return ec2_instance_ids, rds_instance_ids


def _handle_ec2(action, instance_ids):
    if not instance_ids:
        return []
    ec2 = boto3.client("ec2")
    if action == "start":
        ec2.start_instances(InstanceIds=instance_ids)
    else:
        ec2.stop_instances(InstanceIds=instance_ids)
    return instance_ids


def _handle_rds(action, db_identifiers):
    if not db_identifiers:
        return []
    rds = boto3.client("rds")
    handled = []
    for db_id in db_identifiers:
        try:
            if action == "start":
                rds.start_db_instance(DBInstanceIdentifier=db_id)
            else:
                rds.stop_db_instance(DBInstanceIdentifier=db_id)
            handled.append(db_id)
        except rds.exceptions.InvalidDBInstanceStateFault as exc:
            # Ja esta no estado (ou em transicao para o estado) esperado.
            print(f"RDS {db_id}: {exc}")
    return handled


def lambda_handler(event, context):
    action = (event or {}).get("action")
    if action not in ("start", "stop"):
        raise ValueError(f"action invalida: {action!r} (esperado 'start' ou 'stop')")

    arns = _find_tagged_arns()
    ec2_instance_ids, rds_instance_ids = _split_by_service(arns)

    result = {
        "action": action,
        "ec2_instances": _handle_ec2(action, ec2_instance_ids),
        "rds_instances": _handle_rds(action, rds_instance_ids),
    }
    print(result)
    return result
