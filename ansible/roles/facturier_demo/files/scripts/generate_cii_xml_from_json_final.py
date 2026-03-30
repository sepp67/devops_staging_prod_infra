#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import re
import sys
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from xml.etree import ElementTree as ET

Q2 = Decimal("0.01")
Q3 = Decimal("0.001")

NS_RSM = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
NS_RAM = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
NS_UDT = "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"

ET.register_namespace("", NS_RSM)
ET.register_namespace("ram", NS_RAM)
ET.register_namespace("udt", NS_UDT)

# Mapping POC sandbox SUPER PDP
SANDBOX_PARTIES = {
    "burger queen": {
        "global_id": "000000002",
        "legal_id": "000000002",
        "endpoint_id": "315143296_916",
        "vat_number": "FR18000000002",
    },
    "tricatel": {
        "global_id": "000000001",
        "legal_id": "000000001",
        "endpoint_id": "315143296_915",
        "vat_number": "FR15000000001",
    },
}


def q2(value) -> Decimal:
    return Decimal(str(value)).quantize(Q2, rounding=ROUND_HALF_UP)


def q3(value) -> Decimal:
    return Decimal(str(value)).quantize(Q3, rounding=ROUND_HALF_UP)


def extract_digits(value: str) -> str:
    return re.sub(r"\D", "", value or "")


def normalize_country_code(value: str, default="FR") -> str:
    value = (value or default).strip().upper()
    return value if len(value) == 2 and value.isalpha() else default


def country_from_vat(vat_number: str, default="FR") -> str:
    if vat_number and len(vat_number) >= 2 and vat_number[:2].isalpha():
        return vat_number[:2].upper()
    return default


def split_postcode_city(value: str):
    value = (value or "").strip()
    if not value:
        return "", ""
    match = re.match(r"^(\d{4,6})\s+(.+)$", value)
    if match:
        return match.group(1).strip(), match.group(2).strip()
    return "", value


def get_party_siren(raw_value: str):
    digits = extract_digits(raw_value)
    if len(digits) >= 14:
        return digits[:9]
    if len(digits) == 9:
        return digits
    return digits or None


def get_party_global_and_legal_id(raw_value: str):
    return get_party_siren(raw_value)


def normalize_party_address(party: dict) -> dict:
    street = (party.get("street") or "").strip()
    postcode = (party.get("postcode") or "").strip()
    city = (party.get("city") or "").strip()
    country_code = normalize_country_code(
        party.get("country_code") or country_from_vat(party.get("vat_number"), "FR")
    )

    address_lines = party.get("address_lines") or []
    if isinstance(address_lines, str):
        address_lines = [line.strip() for line in address_lines.splitlines() if line.strip()]
    else:
        address_lines = [str(line).strip() for line in address_lines if str(line).strip()]

    if not street and address_lines:
        street = address_lines[0]
    if (not postcode or not city) and len(address_lines) >= 2:
        p, c = split_postcode_city(address_lines[1])
        postcode = postcode or p
        city = city or c
    if len(address_lines) >= 3 and not party.get("country_code"):
        country_code = normalize_country_code(address_lines[2], country_code)

    normalized_lines = [
        part for part in [street, " ".join([v for v in [postcode, city] if v]).strip(), country_code] if part
    ]

    result = dict(party)
    result["street"] = street
    result["postcode"] = postcode
    result["city"] = city
    result["country_code"] = country_code
    result["address_lines"] = normalized_lines
    return result


def enrich_party_for_superpdp(party: dict) -> dict:
    """
    POC sandbox:
    - accepte des valeurs explicites dans le JSON :
      endpoint_id, global_id, legal_id, global_scheme, legal_scheme
    - sinon complète automatiquement Burger Queen / Tricatel
    - lit en priorité le nouveau JSON basé sur siren
    """
    result = normalize_party_address(party)
    name_key = (result.get("name") or "").strip().lower()
    sandbox = SANDBOX_PARTIES.get(name_key, {})

    raw_siren = result.get("siren") or result.get("siret") or result.get("legal_id") or result.get("global_id")
    generic_siren = get_party_siren(raw_siren)

    if generic_siren and not result.get("siren"):
        result["siren"] = generic_siren

    if not result.get("endpoint_id"):
        result["endpoint_id"] = sandbox.get("endpoint_id", "")

    if not result.get("global_id"):
        result["global_id"] = sandbox.get("global_id", "") or generic_siren or ""
    if not result.get("legal_id"):
        result["legal_id"] = sandbox.get("legal_id", "") or generic_siren or ""

    country_code = normalize_country_code(result.get("country_code") or country_from_vat(result.get("vat_number"), "FR"))

    if not result.get("global_scheme"):
        result["global_scheme"] = "0225" if country_code == "FR" else ""
    if not result.get("legal_scheme"):
        result["legal_scheme"] = "0002" if country_code == "FR" else ""

    return result


def unit_to_code(unit: str) -> str:
    u = (unit or "").strip().lower()
    if u in {"kg", "kgs", "kilogramme", "kilogrammes"}:
        return "KGM"
    if u in {"h", "heure", "heures"}:
        return "HUR"
    if u in {"jour", "jours", "j"}:
        return "DAY"
    if u in {"m", "mètre", "mètres", "metre", "metres"}:
        return "MTR"
    return "C62"


def iso_to_102(date_str: str) -> str:
    if re.fullmatch(r"\d{8}", date_str):
        return date_str
    match = re.fullmatch(r"(\d{4})-(\d{2})-(\d{2})", date_str)
    if not match:
        raise ValueError(f"Date invalide: {date_str}. Format attendu YYYY-MM-DD")
    yyyy, mm, dd = match.groups()
    return f"{yyyy}{mm}{dd}"


def compute_invoice(data: dict) -> dict:
    tax_map = defaultdict(lambda: {"basis": Decimal("0.00"), "tax": Decimal("0.00"), "category": "S"})
    computed_lines = []
    total_ht = Decimal("0.00")

    for idx, line in enumerate(data["lines"], start=1):
        qty = Decimal(str(line["quantity"]))
        unit_price = Decimal(str(line["unit_price_ht"]))
        vat_rate = Decimal(str(line["vat_rate"]))

        line_total = q2(qty * unit_price)
        tax_amount = Decimal("0.00") if vat_rate == Decimal("0.00") else q2(line_total * vat_rate / Decimal("100"))
        tax_category = "Z" if vat_rate == Decimal("0.00") else "S"

        computed_line = dict(line)
        computed_line["line_id"] = str(idx).zfill(3)
        computed_line["unit_code"] = unit_to_code(line.get("unit", ""))
        computed_line["quantity"] = q3(qty)
        computed_line["unit_price_ht"] = q2(unit_price)
        computed_line["vat_rate"] = q2(vat_rate)
        computed_line["tax_category"] = tax_category
        computed_line["line_total_ht"] = line_total
        computed_lines.append(computed_line)

        total_ht += line_total
        tax_map[vat_rate]["basis"] += line_total
        tax_map[vat_rate]["tax"] += tax_amount
        tax_map[vat_rate]["category"] = tax_category

    total_ht = q2(total_ht)
    total_tax = q2(sum(v["tax"] for v in tax_map.values()))
    total_ttc = q2(total_ht + total_tax)

    vat_summary = {}
    for rate, values in tax_map.items():
        vat_summary[q2(rate)] = {
            "basis": q2(values["basis"]),
            "tax": q2(values["tax"]),
            "category": values["category"],
        }

    return {
        "lines": computed_lines,
        "tax_summary": vat_summary,
        "totals": {
            "line_total": total_ht,
            "tax_basis_total": total_ht,
            "tax_total": total_tax,
            "grand_total": total_ttc,
            "due_payable": total_ttc,
        },
    }


def rsm(parent, tag):
    return ET.SubElement(parent, f"{{{NS_RSM}}}{tag}")


def ram(parent, tag):
    return ET.SubElement(parent, f"{{{NS_RAM}}}{tag}")


def udt(parent, tag):
    return ET.SubElement(parent, f"{{{NS_UDT}}}{tag}")


def add_structured_postal_address(parent, party: dict):
    addr = ram(parent, "PostalTradeAddress")
    if party.get("postcode"):
        ram(addr, "PostcodeCode").text = party["postcode"]
    if party.get("street"):
        ram(addr, "LineOne").text = party["street"]
    if party.get("city"):
        ram(addr, "CityName").text = party["city"]
    ram(addr, "CountryID").text = party.get("country_code") or "FR"
    return addr


def add_party_identification(parent, party: dict):
    global_scheme = party.get("global_scheme") or "0225"
    legal_scheme = party.get("legal_scheme") or "0002"

    if party.get("global_id"):
        gid = ram(parent, "GlobalID")
        if global_scheme:
            gid.set("schemeID", global_scheme)
        gid.text = party["global_id"]

    if party.get("name"):
        ram(parent, "Name").text = party["name"]

    if party.get("legal_id"):
        org = ram(parent, "SpecifiedLegalOrganization")
        org_id = ram(org, "ID")
        if legal_scheme:
            org_id.set("schemeID", legal_scheme)
        org_id.text = party["legal_id"]

    add_structured_postal_address(parent, party)

    if party.get("endpoint_id"):
        comm = ram(parent, "URIUniversalCommunication")
        uri = ram(comm, "URIID")
        uri.set("schemeID", "0225")
        uri.text = party["endpoint_id"]

    if party.get("vat_number"):
        taxreg = ram(parent, "SpecifiedTaxRegistration")
        vat_id = ram(taxreg, "ID")
        vat_id.set("schemeID", "VA")
        vat_id.text = party["vat_number"]


def build_cii_xml(data: dict) -> ET.ElementTree:
    data = dict(data)
    data["seller"] = enrich_party_for_superpdp(data["seller"])
    data["buyer"] = enrich_party_for_superpdp(data["buyer"])
    calc = compute_invoice(data)

    root = ET.Element(f"{{{NS_RSM}}}CrossIndustryInvoice")

    ctx = rsm(root, "ExchangedDocumentContext")
    bp = ram(ctx, "BusinessProcessSpecifiedDocumentContextParameter")
    ram(bp, "ID").text = "M1"

    guide = ram(ctx, "GuidelineSpecifiedDocumentContextParameter")
    ram(guide, "ID").text = "urn:cen.eu:en16931:2017"

    doc = rsm(root, "ExchangedDocument")
    ram(doc, "ID").text = data["document"]["invoice_number"]
    ram(doc, "TypeCode").text = "380"

    issue_dt = ram(doc, "IssueDateTime")
    dt = udt(issue_dt, "DateTimeString")
    dt.set("format", "102")
    dt.text = iso_to_102(data["document"]["issue_date"])

    for note in data.get("legal_notes", []):
        content = (note or "").strip()
        if not content:
            continue
        note_el = ram(doc, "IncludedNote")
        ram(note_el, "Content").text = content

        lowered = content.lower()
        subject_code = None
        if "escompte" in lowered:
            subject_code = "AAB"
        elif "pénalité" in lowered or "penalite" in lowered:
            subject_code = "PMD"
        elif "recouvrement" in lowered and "40" in lowered:
            subject_code = "PMT"

        if subject_code:
            ram(note_el, "SubjectCode").text = subject_code

    sctt = rsm(root, "SupplyChainTradeTransaction")

    for line in calc["lines"]:
        item = ram(sctt, "IncludedSupplyChainTradeLineItem")

        adoc = ram(item, "AssociatedDocumentLineDocument")
        ram(adoc, "LineID").text = line["line_id"]

        prod = ram(item, "SpecifiedTradeProduct")
        ram(prod, "Name").text = line["description"]

        agr = ram(item, "SpecifiedLineTradeAgreement")
        npp = ram(agr, "NetPriceProductTradePrice")
        ram(npp, "ChargeAmount").text = f"{q2(line['unit_price_ht'])}"

        dlv = ram(item, "SpecifiedLineTradeDelivery")
        qty = ram(dlv, "BilledQuantity")
        qty.set("unitCode", line["unit_code"])
        qty.text = f"{q3(line['quantity'])}"

        stl = ram(item, "SpecifiedLineTradeSettlement")
        tax = ram(stl, "ApplicableTradeTax")
        ram(tax, "TypeCode").text = "VAT"
        ram(tax, "CategoryCode").text = line["tax_category"]
        ram(tax, "RateApplicablePercent").text = f"{q2(line['vat_rate'])}"

        summ = ram(stl, "SpecifiedTradeSettlementLineMonetarySummation")
        ram(summ, "LineTotalAmount").text = f"{q2(line['line_total_ht'])}"

    h_agr = ram(sctt, "ApplicableHeaderTradeAgreement")
    add_party_identification(ram(h_agr, "SellerTradeParty"), data["seller"])
    add_party_identification(ram(h_agr, "BuyerTradeParty"), data["buyer"])

    h_dlv = ram(sctt, "ApplicableHeaderTradeDelivery")
    ship = ram(h_dlv, "ShipToTradeParty")
    ship_addr = ram(ship, "PostalTradeAddress")
    ram(ship_addr, "CountryID").text = country_from_vat(data["buyer"].get("vat_number"), "FR")

    ev = ram(h_dlv, "ActualDeliverySupplyChainEvent")
    occ = ram(ev, "OccurrenceDateTime")
    occ_dt = udt(occ, "DateTimeString")
    occ_dt.set("format", "102")
    occ_dt.text = iso_to_102(data["document"]["issue_date"])

    h_set = ram(sctt, "ApplicableHeaderTradeSettlement")
    ram(h_set, "InvoiceCurrencyCode").text = data["document"].get("currency", "EUR")

    for rate, values in sorted(calc["tax_summary"].items(), key=lambda x: x[0]):
        atax = ram(h_set, "ApplicableTradeTax")
        ram(atax, "CalculatedAmount").text = f"{q2(values['tax'])}"
        ram(atax, "TypeCode").text = "VAT"
        ram(atax, "BasisAmount").text = f"{q2(values['basis'])}"
        ram(atax, "CategoryCode").text = values["category"]
        ram(atax, "RateApplicablePercent").text = f"{q2(rate)}"

    if data["document"].get("due_date"):
        terms = ram(h_set, "SpecifiedTradePaymentTerms")
        due = ram(terms, "DueDateDateTime")
        due_dt = udt(due, "DateTimeString")
        due_dt.set("format", "102")
        due_dt.text = iso_to_102(data["document"]["due_date"])

    msum = ram(h_set, "SpecifiedTradeSettlementHeaderMonetarySummation")
    ram(msum, "LineTotalAmount").text = f"{q2(calc['totals']['line_total'])}"
    ram(msum, "TaxBasisTotalAmount").text = f"{q2(calc['totals']['tax_basis_total'])}"

    tax_total = ram(msum, "TaxTotalAmount")
    tax_total.set("currencyID", data["document"].get("currency", "EUR"))
    tax_total.text = f"{q2(calc['totals']['tax_total'])}"

    ram(msum, "GrandTotalAmount").text = f"{q2(calc['totals']['grand_total'])}"
    ram(msum, "DuePayableAmount").text = f"{q2(calc['totals']['due_payable'])}"

    return ET.ElementTree(root)


def main():
    if len(sys.argv) != 3:
        print("Usage: python generate_cii_xml_from_json_poc.py invoice.json output.cii.xml")
        sys.exit(1)

    json_path = Path(sys.argv[1])
    xml_path = Path(sys.argv[2])

    with json_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    required = [
        ("document.invoice_number", data.get("document", {}).get("invoice_number")),
        ("document.issue_date", data.get("document", {}).get("issue_date")),
        ("seller.name", data.get("seller", {}).get("name")),
        ("buyer.name", data.get("buyer", {}).get("name")),
    ]
    missing = [k for k, v in required if not v]
    if missing:
        raise ValueError(f"Champs obligatoires manquants: {', '.join(missing)}")

    tree = build_cii_xml(data)
    tree.write(xml_path, encoding="utf-8", xml_declaration=True)
    print(f"XML CII généré : {xml_path}")


if __name__ == "__main__":
    main()
