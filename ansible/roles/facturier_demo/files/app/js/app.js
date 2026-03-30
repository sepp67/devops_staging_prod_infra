    const linesBody = document.getElementById('lines-body');
    const vatSummaryBody = document.getElementById('vat-summary-body');
    const totalLinesEl = document.getElementById('total-lines-ht');
    const taxBaseEl = document.getElementById('tax-base-total');
    const taxTotalEl = document.getElementById('tax-total');
    const grandTotalEl = document.getElementById('grand-total');
    const duePayableEl = document.getElementById('due-payable');
    const currencySelect = document.getElementById('currency');
    const customerTypeEl = document.getElementById('customer-type');
    const validationBadgesEl = document.getElementById('validation-badges');
    const suggestionsEl = document.getElementById('suggestions');

    function parseNum(value) {
      const n = parseFloat(String(value).replace(',', '.'));
      return Number.isFinite(n) ? n : 0;
    }

    function round2(n) {
      return Math.round((n + Number.EPSILON) * 100) / 100;
    }

    function cleanDigits(value) {
      return String(value || '').replace(/\D/g, '');
    }

    function formatMoney(n) {
      return round2(n).toFixed(2) + ' ' + currencySelect.value;
    }

    function buildPartyIdentifiers(countryCode, sirenValue) {
      const country = String(countryCode || 'FR').trim().toUpperCase() || 'FR';
      const siren = cleanDigits(sirenValue);

      if (!siren) {
        return {
          siren: '',
          global_id: '',
          global_scheme: '',
          legal_id: '',
          legal_scheme: ''
        };
      }

      if (country === 'FR') {
        return {
          siren,
          global_id: siren,
          global_scheme: '0225',
          legal_id: siren,
          legal_scheme: '0002'
        };
      }

      return {
        siren,
        global_id: siren,
        global_scheme: '',
        legal_id: siren,
        legal_scheme: ''
      };
    }

    function bindRow(row) {
      row.querySelectorAll('input, textarea').forEach((el) => {
        el.addEventListener('input', () => {
          recalc();
          updateValidationUI();
        });
      });

      const removeBtn = row.querySelector('.remove-line');
      if (removeBtn) {
        removeBtn.addEventListener('click', () => {
          row.remove();
          recalc();
          updateValidationUI();
        });
      }
    }

    function recalc() {
      const rows = [...linesBody.querySelectorAll('tr')];
      const vatMap = new Map();
      let totalHT = 0;

      rows.forEach((row) => {
        const qty = parseNum(row.querySelector('.qty')?.value || 0);
        const unitPrice = parseNum(row.querySelector('.unit-price')?.value || 0);
        const vatRate = parseNum(row.querySelector('.vat-rate')?.value || 0);
        const lineTotal = round2(qty * unitPrice);

        row.querySelector('.line-total').textContent = lineTotal.toFixed(2);
        totalHT += lineTotal;

        const current = vatMap.get(vatRate) || { base: 0, tax: 0 };
        current.base += lineTotal;
        current.tax += round2(lineTotal * vatRate / 100);
        vatMap.set(vatRate, current);
      });

      totalHT = round2(totalHT);
      let totalTax = 0;
      vatSummaryBody.innerHTML = '';

      [...vatMap.entries()].sort((a, b) => a[0] - b[0]).forEach(([rate, values]) => {
        const base = round2(values.base);
        const tax = round2(values.tax);
        totalTax += tax;

        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td class="num">${base.toFixed(2)} ${currencySelect.value}</td>
          <td class="num">${rate.toFixed(2)} %</td>
          <td class="num">${tax.toFixed(2)} ${currencySelect.value}</td>
        `;
        vatSummaryBody.appendChild(tr);
      });

      totalTax = round2(totalTax);
      const grandTotal = round2(totalHT + totalTax);

      totalLinesEl.textContent = formatMoney(totalHT);
      taxBaseEl.textContent = formatMoney(totalHT);
      taxTotalEl.textContent = formatMoney(totalTax);
      grandTotalEl.textContent = formatMoney(grandTotal);
      duePayableEl.textContent = formatMoney(grandTotal);
    }

    function getField(id) {
      return document.getElementById(id);
    }

    function setFieldState(fieldId, state) {
      const field = document.getElementById(fieldId);
      if (!field) return;
      field.classList.remove('field-warning', 'field-danger');
      if (state === 'warning') field.classList.add('field-warning');
      if (state === 'danger') field.classList.add('field-danger');
    }

    function addBadge(text, variant = 'success') {
      const div = document.createElement('div');
      div.className = `status-badge ${variant}`;
      div.textContent = text;
      validationBadgesEl.appendChild(div);
    }

    function addSuggestion(title, message, actionLabel, action) {
      const item = document.createElement('div');
      item.className = 'suggestion-item';
      const h3 = document.createElement('h3');
      h3.textContent = title;
      const p = document.createElement('p');
      p.textContent = message;
      item.appendChild(h3);
      item.appendChild(p);
      if (actionLabel && typeof action === 'function') {
        const helper = document.createElement('div');
        helper.className = 'helper-row';
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'btn secondary';
        btn.textContent = actionLabel;
        btn.addEventListener('click', action);
        helper.appendChild(btn);
        item.appendChild(helper);
      }
      suggestionsEl.appendChild(item);
    }

    function analyzeValidation() {
      const customerType = customerTypeEl.value;
      const buyerSiren = cleanDigits(getField('buyer-siren').value);
      const buyerName = getField('buyer-name').value.trim();
      const buyerStreet = getField('buyer-street').value.trim();
      const buyerPostcode = getField('buyer-postcode').value.trim();
      const buyerCity = getField('buyer-city').value.trim();
      const sellerSiren = cleanDigits(getField('seller-siren').value);
      const sellerName = getField('seller-name').value.trim();
      const invoiceNumber = getField('invoice-number').value.trim();
      const rows = [...linesBody.querySelectorAll('tr')];
      const hasLines = rows.length > 0;

      const result = {
        status: 'ok',
        badges: [],
        suggestions: []
      };

      if (!sellerName || !sellerSiren || !invoiceNumber || !hasLines) {
        result.status = 'danger';
        result.badges.push(['Informations incomplètes', 'danger']);
      }

      if (customerType === 'business') {
        result.badges.push(['Flux B2B : préparation e-invoicing', 'success']);
        if (!buyerSiren) {
          result.status = 'danger';
          result.badges.push(['SIREN client manquant', 'danger']);
          result.suggestions.push({
            title: 'Compléter le SIREN du client',
            message: 'Dans un cas B2B français, l’absence d’identifiant client peut bloquer la validation métier côté PDP.',
            actionLabel: 'Passer le client en “Particulier”',
            action: () => {
              customerTypeEl.value = 'private';
              updateValidationUI();
            }
          });
        }
        if (!buyerStreet || !buyerPostcode || !buyerCity) {
          result.status = 'danger';
          result.badges.push(['Adresse client incomplète', 'danger']);
          result.suggestions.push({
            title: 'Structurer l’adresse du client',
            message: 'Sépare bien la rue, le code postal et la ville. C’est un point souvent bloquant pour la validation.',
          });
        }
      } else {
        result.badges.push(['Flux B2C : pas d’envoi PDP direct', 'warning']);
        if (!buyerName) {
          result.status = 'warning';
          result.suggestions.push({
            title: 'Compléter le nom du client',
            message: 'Même pour un particulier, il faut garder une facture lisible et exploitable localement.'
          });
        }
      }

      if (!hasLines) {
        result.suggestions.push({
          title: 'Ajouter au moins une ligne de facture',
          message: 'Le document doit contenir au minimum une prestation ou un produit pour être exploitable.',
          actionLabel: 'Ajouter une ligne',
          action: () => document.getElementById('add-line').click()
        });
      }

      const rowsWithZero = rows.filter((row) => parseNum(row.querySelector('.qty')?.value || 0) <= 0 || parseNum(row.querySelector('.unit-price')?.value || 0) < 0);
      if (rowsWithZero.length) {
        result.status = result.status === 'danger' ? 'danger' : 'warning';
        result.badges.push(['Certaines lignes sont à vérifier', 'warning']);
        result.suggestions.push({
          title: 'Vérifier quantité et prix unitaire',
          message: 'Une ou plusieurs lignes semblent incohérentes. Corrige les quantités ou les prix avant export.'
        });
      }

      if (result.badges.length === 0) {
        result.badges.push(['Facture prête pour export', 'success']);
      }

      if (result.suggestions.length === 0) {
        result.suggestions.push({
          title: 'Aucune alerte bloquante détectée',
          message: 'Tu peux exporter le JSON ou imprimer le document pour la suite du pipeline.'
        });
      }

      return result;
    }

    function updateCustomerModeUI() {
      const business = customerTypeEl.value === 'business';
      setFieldState('buyer-siren-field', business && !cleanDigits(getField('buyer-siren').value) ? 'danger' : null);
      setFieldState('buyer-postcode-field', business && !getField('buyer-postcode').value.trim() ? 'danger' : null);
      setFieldState('buyer-city-field', business && !getField('buyer-city').value.trim() ? 'danger' : null);
      setFieldState('buyer-street-field', business && !getField('buyer-street').value.trim() ? 'warning' : null);
      setFieldState('buyer-vat-field', business && !getField('buyer-vat').value.trim() ? 'warning' : null);
    }

    function updateValidationUI() {
      updateCustomerModeUI();
      validationBadgesEl.innerHTML = '';
      suggestionsEl.innerHTML = '';
      const result = analyzeValidation();
      result.badges.forEach(([text, variant]) => addBadge(text, variant));
      result.suggestions.forEach((item) => addSuggestion(item.title, item.message, item.actionLabel, item.action));
    }

    function collectInvoiceData() {
      const rows = [...linesBody.querySelectorAll('tr')];
      const lines = rows.map((row) => {
        const qty = parseNum(row.querySelector('.qty')?.value || 0);
        const unitPrice = parseNum(row.querySelector('.unit-price')?.value || 0);
        const vatRate = parseNum(row.querySelector('.vat-rate')?.value || 0);
        return {
          code: row.cells[0].querySelector('input')?.value?.trim() || '',
          description: row.cells[1].querySelector('textarea')?.value?.trim() || '',
          quantity: qty,
          unit: row.cells[3].querySelector('input')?.value?.trim() || 'u',
          unit_price_ht: round2(unitPrice),
          vat_rate: round2(vatRate)
        };
      });

      const sellerCountry = getField('seller-country').value.trim() || 'FR';
      const buyerCountry = getField('buyer-country').value.trim() || 'FR';
      const sellerIdentifiers = buildPartyIdentifiers(sellerCountry, getField('seller-siren').value.trim());
      const buyerIdentifiers = buildPartyIdentifiers(buyerCountry, getField('buyer-siren').value.trim());

      return {
        document: {
          title: 'Facture électronique simple',
          invoice_number: getField('invoice-number').value.trim(),
          issue_date: getField('invoice-date').value,
          due_date: getField('due-date').value,
          currency: getField('currency').value,
          customer_type: getField('customer-type').value
        },
        seller: {
          name: getField('seller-name').value.trim(),
          siren: sellerIdentifiers.siren,
          vat_number: getField('seller-vat').value.trim(),
          street: getField('seller-street').value.trim(),
          postcode: getField('seller-postcode').value.trim(),
          city: getField('seller-city').value.trim(),
          country_code: sellerCountry,
          email: getField('seller-email').value.trim(),
          phone: getField('seller-phone').value.trim(),
          global_id: sellerIdentifiers.global_id,
          global_scheme: sellerIdentifiers.global_scheme,
          legal_id: sellerIdentifiers.legal_id,
          legal_scheme: sellerIdentifiers.legal_scheme
        },
        buyer: {
          name: getField('buyer-name').value.trim(),
          siren: buyerIdentifiers.siren,
          vat_number: getField('buyer-vat').value.trim(),
          street: getField('buyer-street').value.trim(),
          postcode: getField('buyer-postcode').value.trim(),
          city: getField('buyer-city').value.trim(),
          country_code: buyerCountry,
          email: getField('buyer-email').value.trim(),
          phone: getField('buyer-phone').value.trim(),
          global_id: buyerIdentifiers.global_id,
          global_scheme: buyerIdentifiers.global_scheme,
          legal_id: buyerIdentifiers.legal_id,
          legal_scheme: buyerIdentifiers.legal_scheme
        },
        lines,
        legal_notes: [
          getField('legal-1').value.trim(),
          getField('legal-2').value.trim(),
          getField('legal-3').value.trim()
        ].filter(Boolean),
        payment: {
          iban: getField('iban').value.trim()
        }
      };
    }

    function exportJson() {
      recalc();
      updateValidationUI();
      const data = collectInvoiceData();
      const invoiceNumber = data.document.invoice_number || 'invoice';
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${invoiceNumber}.json`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 100);
    }

    function exportSummary() {
      recalc();
      updateValidationUI();
      const data = collectInvoiceData();
      const summary = [
        `Facture : ${data.document.invoice_number}`,
        `Type client : ${data.document.customer_type === 'business' ? 'Entreprise' : 'Particulier'}`,
        `Date : ${data.document.issue_date}`,
        `Émetteur : ${data.seller.name}`,
        `Client : ${data.buyer.name}`,
        `Nombre de lignes : ${data.lines.length}`,
        `Total TTC : ${grandTotalEl.textContent}`
      ].join('\n');

      const blob = new Blob([summary], { type: 'text/plain;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${data.document.invoice_number || 'invoice'}-recap.txt`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 100);
    }

    document.querySelectorAll('#lines-body tr').forEach(bindRow);

    document.querySelectorAll('input, textarea, select').forEach((el) => {
      el.addEventListener('input', () => {
        recalc();
        updateValidationUI();
      });
      el.addEventListener('change', () => {
        recalc();
        updateValidationUI();
      });
    });

    document.getElementById('add-line').addEventListener('click', () => {
      const tpl = document.getElementById('line-template');
      const fragment = tpl.content.cloneNode(true);
      const row = fragment.querySelector('tr');
      linesBody.appendChild(row);
      bindRow(row);
      recalc();
      updateValidationUI();
    });

    document.getElementById('export-json').addEventListener('click', exportJson);
    document.getElementById('export-summary').addEventListener('click', exportSummary);

    recalc();
    updateValidationUI();
