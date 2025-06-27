#!/bin/bash
# SLA Reporting Templates for Service Desk Intervention Timing
# These templates focus on intervention timing requirements rather than RPO/RTO

# SLA Tier Definitions
declare -A SLA_TIERS=(
    ["CRITICAL"]="15min,24x7,immediate,critical"
    ["HIGH"]="1hour,business_hours,urgent,high" 
    ["STANDARD"]="4hours,business_hours,normal,medium"
    ["LOW"]="24hours,business_hours,when_possible,low"
)

# Generate SLA assessment report
generate_sla_report() {
    local raw_data="$1"
    local output_format="$2"
    local hostname=$(hostname)
    local timestamp=$(date -Iseconds)
    
    # Analyze environment for SLA classification
    local suggested_tier=$(determine_sla_tier "$raw_data")
    local environment_complexity=$(assess_complexity "$raw_data")
    local support_requirements=$(assess_support_requirements "$raw_data")
    
    case "$output_format" in
        "json")
            generate_json_sla_report "$hostname" "$timestamp" "$suggested_tier" "$environment_complexity" "$support_requirements"
            ;;
        "csv")
            generate_csv_sla_report "$hostname" "$timestamp" "$suggested_tier" "$environment_complexity" "$support_requirements"
            ;;
        *)
            generate_text_sla_report "$hostname" "$timestamp" "$suggested_tier" "$environment_complexity" "$support_requirements"
            ;;
    esac
}

# Determine appropriate SLA tier based on environment analysis
determine_sla_tier() {
    local data="$1"
    local score=0
    
    # Database criticality indicators
    if echo "$data" | grep -qi "replication\|cluster\|primary\|master"; then
        score=$((score + 30))
    fi
    
    # High availability setup
    if echo "$data" | grep -qi "galera\|streaming.*replication\|hot.*standby"; then
        score=$((score + 25))
    fi
    
    # Large databases (>100GB indicates production)
    if echo "$data" | grep -qi "size.*[0-9]\+G\|size.*TB"; then
        score=$((score + 20))
    fi
    
    # Production indicators
    if echo "$data" | grep -qi "prod\|production\|prd"; then
        score=$((score + 25))
    fi
    
    # Multiple databases
    local db_count=$(echo "$data" | grep -c "Database:")
    if [ "$db_count" -gt 5 ]; then
        score=$((score + 15))
    fi
    
    # Suggest tier based on score
    if [ "$score" -ge 70 ]; then
        echo "CRITICAL"
    elif [ "$score" -ge 50 ]; then
        echo "HIGH"
    elif [ "$score" -ge 30 ]; then
        echo "STANDARD"
    else
        echo "LOW"
    fi
}

# Assess environment complexity for support planning
assess_complexity() {
    local data="$1"
    local complexity="LOW"
    local factors=()
    
    # Multiple database engines
    local engines=0
    echo "$data" | grep -qi "postgresql" && engines=$((engines + 1))
    echo "$data" | grep -qi "mysql" && engines=$((engines + 1))
    echo "$data" | grep -qi "mariadb" && engines=$((engines + 1))
    
    if [ "$engines" -gt 1 ]; then
        complexity="HIGH"
        factors+=("Multiple database engines")
    fi
    
    # Replication setup
    if echo "$data" | grep -qi "replication.*status.*replicating\|cluster.*status.*primary"; then
        complexity="MEDIUM"
        factors+=("Active replication/clustering")
    fi
    
    # Custom paths (OFA or non-standard)
    if echo "$data" | grep -qi "/u01/\|/u02/\|/opt/.*product"; then
        complexity="MEDIUM"
        factors+=("Custom/OFA installation paths")
    fi
    
    # Large number of databases
    local db_count=$(echo "$data" | grep -c -i "database.*:")
    if [ "$db_count" -gt 10 ]; then
        complexity="HIGH"
        factors+=("Large number of databases ($db_count)")
    fi
    
    echo "$complexity|${factors[*]}"
}

# Assess support requirements based on environment
assess_support_requirements() {
    local data="$1"
    local requirements=()
    
    # Database-specific expertise needed
    echo "$data" | grep -qi "postgresql" && requirements+=("PostgreSQL DBA expertise")
    echo "$data" | grep -qi "mysql" && requirements+=("MySQL DBA expertise") 
    echo "$data" | grep -qi "mariadb" && requirements+=("MariaDB DBA expertise")
    
    # High availability expertise
    if echo "$data" | grep -qi "galera\|streaming.*replication\|cluster"; then
        requirements+=("High Availability/Clustering expertise")
    fi
    
    # Performance tuning needs
    if echo "$data" | grep -qi "slow.*log\|performance.*schema"; then
        requirements+=("Performance tuning expertise")
    fi
    
    # Security requirements
    if echo "$data" | grep -qi "ssl.*enabled\|users.*count.*[0-9]\+"; then
        requirements+=("Database security management")
    fi
    
    # Backup management
    if echo "$data" | grep -qi "backup.*config\|archive.*mode"; then
        requirements+=("Backup and recovery management")
    fi
    
    echo "${requirements[*]}"
}

# Generate JSON SLA report
generate_json_sla_report() {
    local hostname="$1"
    local timestamp="$2"
    local tier="$3"
    local complexity="$4"
    local requirements="$5"
    
    local complexity_level=$(echo "$complexity" | cut -d'|' -f1)
    local complexity_factors=$(echo "$complexity" | cut -d'|' -f2)
    
    IFS=',' read -r response_time coverage urgency priority <<< "${SLA_TIERS[$tier]}"
    
    cat <<EOF
{
  "sla_assessment": {
    "metadata": {
      "hostname": "$hostname",
      "assessment_date": "$timestamp",
      "assessment_version": "1.0"
    },
    "sla_recommendation": {
      "tier": "$tier",
      "response_time": "$response_time",
      "coverage": "$coverage",
      "urgency_level": "$urgency",
      "priority": "$priority"
    },
    "environment_analysis": {
      "complexity_level": "$complexity_level",
      "complexity_factors": "$complexity_factors",
      "support_requirements": "$requirements"
    },
    "service_desk_guidelines": {
      "initial_response": "$response_time",
      "escalation_triggers": [
        "Database service unavailable",
        "Performance degradation >50%",
        "Replication failures",
        "Backup failures",
        "Security incidents"
      ],
      "required_information": [
        "Error messages and logs",
        "Recent changes or deployments",
        "Performance impact assessment", 
        "Business process affected"
      ],
      "common_issues": [
        "Connection timeouts",
        "Slow query performance",
        "Disk space issues",
        "Lock contention",
        "Replication lag"
      ]
    },
    "dba_handoff_criteria": {
      "immediate_escalation": [
        "Data corruption suspected",
        "Primary database unavailable",
        "Cluster split-brain scenarios"
      ],
      "scheduled_escalation": [
        "Performance optimization requests",
        "Schema changes",
        "Backup strategy modifications"
      ]
    }
  }
}
EOF
}

# Generate CSV SLA report
generate_csv_sla_report() {
    local hostname="$1"
    local timestamp="$2" 
    local tier="$3"
    local complexity="$4"
    local requirements="$5"
    
    local complexity_level=$(echo "$complexity" | cut -d'|' -f1)
    IFS=',' read -r response_time coverage urgency priority <<< "${SLA_TIERS[$tier]}"
    
    echo "Field,Value"
    echo "Hostname,$hostname"
    echo "Assessment Date,$timestamp"
    echo "SLA Tier,$tier"
    echo "Response Time,$response_time"
    echo "Coverage,$coverage"
    echo "Urgency Level,$urgency"
    echo "Priority,$priority"
    echo "Complexity Level,$complexity_level"
    echo "Support Requirements,\"$requirements\""
}

# Generate text SLA report
generate_text_sla_report() {
    local hostname="$1"
    local timestamp="$2"
    local tier="$3" 
    local complexity="$4"
    local requirements="$5"
    
    local complexity_level=$(echo "$complexity" | cut -d'|' -f1)
    local complexity_factors=$(echo "$complexity" | cut -d'|' -f2)
    IFS=',' read -r response_time coverage urgency priority <<< "${SLA_TIERS[$tier]}"
    
    cat <<EOF

=================================================================
                    SLA ASSESSMENT REPORT
=================================================================

System Information:
  Hostname: $hostname
  Assessment Date: $timestamp
  
SLA Recommendation:
  Tier: $tier
  Response Time: $response_time
  Coverage: $coverage  
  Urgency Level: $urgency
  Priority: $priority

Environment Analysis:
  Complexity Level: $complexity_level
  Complexity Factors: $complexity_factors
  
Support Requirements:
  $requirements

Service Desk Guidelines:
  ✓ Initial Response: $response_time
  ✓ Escalate immediately for: Database outages, corruption, security incidents
  ✓ Collect: Error messages, recent changes, performance impact, affected processes
  ✓ Common Issues: Connection timeouts, slow queries, disk space, locks, replication lag

DBA Escalation Criteria:
  Immediate: Data corruption, primary DB down, cluster issues
  Scheduled: Performance tuning, schema changes, backup modifications

=================================================================
EOF
}

# Integration function for main script
add_sla_assessment_to_report() {
    local report_data="$1"
    local format="$2"
    
    echo ""
    echo "=== SLA ASSESSMENT ==="
    generate_sla_report "$report_data" "$format"
}