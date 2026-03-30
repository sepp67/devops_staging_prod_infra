#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import sys
from pathlib import Path

try:
    from facturx import generate_from_file
except ImportError as exc:
    raise SystemExit(
        "Le module facturx est manquant. Installez les dépendances avec : pip install reportlab factur-x"
    ) from exc

from generate_cii_xml_from_json_poc_v2 import build_cii_xml, enrich_party_for_superpdp
from generate_invoice_pdf_poc_v2 import generate_pdf


def validate_input(data: dict):
    required = [
        ("document.invoice_number", data.get("document", {}).get("invoice_number")),
        ("document.issue_date", data.get("document", {}).get("issue_date")),
        ("seller.name", data.get("seller", {}).get("name")),
        ("buyer.name", data.get("buyer", {}).get("name")),
    ]
    missing = [k for k, v in required if not v]
    if missing:
        raise ValueError(f"Champs obligatoires manquants: {', '.join(missing)}")
    if not data.get("lines"):
        raise ValueError("La facture doit contenir au moins une ligne.")

    for role in ("seller", "buyer"):
        party = enrich_party_for_superpdp(data.get(role, {}))
        if not party.get("endpoint_id"):
            raise ValueError(
                f"{role}.endpoint_id manquant. "
                "Pour le POC sandbox, utilisez les valeurs d'annuaire SUPER PDP "
                "(Burger Queen = 315143296_916, Tricatel = 315143296_915) "
                "ou renseignez endpoint_id explicitement dans le JSON."
            )
        if not party.get("global_id") or not party.get("legal_id"):
            raise ValueError(
                f"{role}.global_id / {role}.legal_id manquants. "
                "Pour le POC sandbox, ils peuvent être complétés automatiquement "
                "pour Burger Queen / Tricatel, sinon fournissez-les dans le JSON."
            )


def build_output_paths(json_path: Path, output_dir: Path | None = None):
    stem = json_path.stem
    base_dir = output_dir if output_dir else json_path.parent
    return {
        "pdf": base_dir / f"{stem}.pdf",
        "xml": base_dir / f"{stem}.cii.xml",
        "facturx_pdf": base_dir / f"{stem}_facturx.pdf",
    }


def generate_cii_xml(data: dict, xml_path: Path):
    tree = build_cii_xml(data)
    tree.write(xml_path, encoding="utf-8", xml_declaration=True)


def generate_all_from_json(json_path: Path, output_dir: Path | None = None):
    with json_path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    validate_input(data)

    paths = build_output_paths(json_path, output_dir)
    paths["pdf"].parent.mkdir(parents=True, exist_ok=True)

    print(f"📥 JSON chargé : {json_path}")

    generate_pdf(data, paths["pdf"])
    print(f"📄 PDF généré : {paths['pdf']}")

    generate_cii_xml(data, paths["xml"])
    print(f"🧾 XML CII généré : {paths['xml']}")

    generate_from_file(
        str(paths["pdf"]),
        str(paths["xml"]),
        output_pdf_file=str(paths["facturx_pdf"]),
    )
    print(f"📦 Factur-X généré : {paths['facturx_pdf']}")

    return paths


def main():
    if len(sys.argv) not in {2, 3}:
        print("Usage: python generate_facturx_from_json_poc.py invoice.json [output_dir]")
        sys.exit(1)

    json_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2]) if len(sys.argv) == 3 else None

    try:
        paths = generate_all_from_json(json_path, output_dir)
        print("✅ Génération terminée")
        print(f"   PDF      : {paths['pdf']}")
        print(f"   XML CII  : {paths['xml']}")
        print(f"   Factur-X : {paths['facturx_pdf']}")
    except Exception as exc:
        print(f"❌ Erreur : {exc}")
        sys.exit(2)


if __name__ == "__main__":
    main()
