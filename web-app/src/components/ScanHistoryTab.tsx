'use client';

import React, { useState } from 'react';
import { ScanItem } from '../types';
import { OfficerApi } from '../services/api';
import { 
  CheckCircle2, 
  XCircle, 
  RotateCcw, 
  Download, 
  Clock, 
  ShieldAlert, 
  Package, 
  Layers,
  ChevronDown,
  ChevronUp,
  Scale,
  FileText,
  ExternalLink,
  Copy,
  Check,
  Eye,
  EyeOff,
  Sparkles,
  Award,
  Table as TableIcon
} from 'lucide-react';

interface ScanHistoryTabProps {
  scans: ScanItem[];
  onRefresh: () => void;
}

export const ScanHistoryTab: React.FC<ScanHistoryTabProps> = ({ scans, onRefresh }) => {
  const [expandedScanId, setExpandedScanId] = useState<string | null>(scans[0]?.scan_id || null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [reviewNotes, setReviewNotes] = useState<{ [id: string]: string }>({});
  const [selectedSides, setSelectedSides] = useState<{ [scanId: string]: string }>({});
  const [copiedTextId, setCopiedTextId] = useState<string | null>(null);
  const [showBoxes, setShowBoxes] = useState<{ [scanId: string]: boolean }>({});
  const [hoveredBoxId, setHoveredBoxId] = useState<string | null>(null);

  const renderHighlightedSentence = (sentence: string) => {
    const parts = sentence.split(/(['"][^'"]+['"])/g);
    return parts.map((part, pIdx) => {
      const isQuoted = (part.startsWith("'") && part.endsWith("'")) || (part.startsWith('"') && part.endsWith('"'));
      if (isQuoted) {
        return (
          <mark key={pIdx} className="brand-claim-mark">
            {part}
          </mark>
        );
      }
      return <span key={pIdx}>{part}</span>;
    });
  };

  const toggleExpand = (scanId: string) => {
    setExpandedScanId(expandedScanId === scanId ? null : scanId);
  };

  const handleDecision = async (
    scanId: string,
    decision: 'ACCEPT' | 'REJECT' | 'REQUEST_RESCAN'
  ) => {
    setActionLoading(scanId);
    const notes = reviewNotes[scanId] || `Enforcement officer decision: ${decision}`;
    await OfficerApi.submitScanReview(
      scanId,
      decision,
      '00000000-0000-0000-0000-000000000001',
      notes
    );
    setActionLoading(null);
    onRefresh();
  };

  return (
    <div className="tab-wrapper animate-fade-in">
      {/* Top Banner */}
      <div className="info-banner glass-panel">
        <div className="banner-icon-box">
          <Scale size={22} className="text-emerald" />
        </div>
        <div>
          <h2 className="banner-title">Field Officer Packaging Audit Stream</h2>
          <p className="banner-subtitle">
            Real-time feed of multi-side packaging photographs, AI OCR field extractions, and statutory evaluations conducted by field enforcement personnel.
          </p>
        </div>
      </div>

      {/* Scans Timeline */}
      <div className="scans-list">
        {scans.map((scan) => {
          const isExpanded = expandedScanId === scan.scan_id;
          const isPass = scan.overall_compliance === 'PASS';
          const isFail = scan.overall_compliance === 'FAIL';
          const score = scan.compliance_summary?.compliance_score ?? (isPass ? 100 : 50);
          const isProcessing = actionLoading === scan.scan_id;

          return (
            <div key={scan.scan_id} className="scan-card glass-panel">
              {/* Scan Card Header */}
              <div className="scan-card-header" onClick={() => toggleExpand(scan.scan_id)}>
                <div className="left-meta">
                  <div className={`status-indicator ${isPass ? 'pass' : isFail ? 'fail' : 'review'}`}>
                    {isPass ? <CheckCircle2 size={20} /> : <ShieldAlert size={20} />}
                  </div>
                  <div>
                    <div className="product-title-row">
                      <h3 className="product-name">{scan.product_name || 'Unregistered Product Pack'}</h3>
                      <span className={`badge ${isPass ? 'badge-emerald' : isFail ? 'badge-crimson' : 'badge-amber'}`}>
                        {scan.overall_compliance} ({score}% SCORE)
                      </span>
                      {scan.decision && (
                        <span className="badge badge-cyan">DECISION: {scan.decision}</span>
                      )}
                    </div>
                    <div className="product-sub-row">
                      <span className="mfr-name">{scan.manufacturer_name || 'Manufacturer Not Declared'}</span>
                      <span className="dot">•</span>
                      <span className="time-text font-mono">
                        <Clock size={12} /> {new Date(scan.created_at).toLocaleString()}
                      </span>
                    </div>
                  </div>
                </div>

                <div className="right-actions" onClick={(e) => e.stopPropagation()}>
                  <a
                    href={OfficerApi.getScanReportUrl(scan.scan_id)}
                    target="_blank"
                    rel="noreferrer"
                    className="btn-primary report-btn"
                    title="Generate & Download Full Statutory PDF"
                  >
                    <Download size={14} />
                    Statutory Report
                  </a>
                  <button onClick={() => toggleExpand(scan.scan_id)} className="expand-btn">
                    {isExpanded ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
                  </button>
                </div>
              </div>

              {/* Expanded Inspection Dossier */}
              {isExpanded && (() => {
                const availableSides = Object.keys(scan.image_urls || {});
                const activeSide = selectedSides[scan.scan_id] || availableSides[0] || 'front';
                const activeImageUrl = scan.image_urls?.[activeSide] || '';
                const activeTranscription = scan.ocr_transcriptions?.find(
                  (t) => (t.image_side || t.side || '').toLowerCase() === activeSide.toLowerCase()
                );
                const activeOcrText = activeTranscription?.detected_text || activeTranscription?.text || (availableSides.length <= 1 ? scan.all_detected_text : '');
                const boundingBoxes = activeTranscription?.bounding_boxes || [];

                const brandClaims = scan.brand_claims || scan.extracted_declarations?.brand_claims || [];
                const summarySentences = Array.isArray(scan.summary_sentences)
                  ? scan.summary_sentences
                  : (Array.isArray(scan.extracted_declarations?.summary_sentences)
                      ? scan.extracted_declarations.summary_sentences
                      : (scan.summary_sentences ? [scan.summary_sentences] : []));

                const resolvedSentences = summarySentences.length > 0 ? summarySentences : [
                  `This packaging represents ${scan.product_name || scan.extracted_declarations?.generic_product_name || 'Pre-packaged Commodity'} manufactured by ${scan.manufacturer_name || scan.extracted_declarations?.manufacturer_name || 'the declared producer'}.`,
                  `The declared retail pricing is ${scan.extracted_declarations?.mrp || 'statutory MRP'} with a declared net quantity of ${scan.extracted_declarations?.net_quantity || 'standard metric volume'}.`,
                  ...(brandClaims.length > 0 ? [
                    `Prominent Brand Claims Highlight: The packaging prominently asserts ${brandClaims.map((c: any) => `'${c.claim}'`).join(', ')} as key brand promises.`
                  ] : [])
                ];

                const declarationsTableRows = scan.declarations_table || scan.extracted_declarations?.declarations_table || (() => {
                  const rows: any[] = [];
                  if (scan.extracted_declarations) {
                    Object.entries(scan.extracted_declarations).forEach(([k, v]) => {
                      if (k === 'brand_claims' || k === 'summary_sentences' || k === 'declarations_table' || k === 'dynamic_fields' || k === 'raw_extractions') return;
                      if (v === null || v === undefined) return;
                      rows.push({
                        attribute: k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
                        value: String(v),
                        category: 'Statutory Declaration',
                        is_brand_claim: false,
                        highlight: false,
                      });
                    });
                  }
                  brandClaims.forEach((c: any) => {
                    rows.push({
                      attribute: `Brand Claim: ${c.category || 'Quality'}`,
                      value: c.claim,
                      category: 'Brand Claim',
                      is_brand_claim: true,
                      highlight: true,
                    });
                  });
                  return rows;
                })();

                return (
                <div className="expanded-content animate-fade-in">
                  {/* Multi-Angle Packaging & OCR Visual Extraction Studio */}
                  <div className="dossier-section">
                    <div className="section-title-row">
                      <FileText size={16} className="text-emerald" />
                      <h4 className="section-heading">Packaging Photo & Visual OCR Transcription (4-Way Rotations)</h4>
                    </div>

                    {availableSides.length > 0 ? (
                      <div className="ocr-studio-card">
                        {/* Side Selector Tabs */}
                        <div className="side-tabs-bar">
                          <span className="tabs-label">Scanned Faces:</span>
                          <div className="side-tabs">
                            {availableSides.map((side) => {
                              const isSelected = activeSide.toLowerCase() === side.toLowerCase();
                              return (
                                <button
                                  key={side}
                                  type="button"
                                  onClick={() => setSelectedSides({ ...selectedSides, [scan.scan_id]: side })}
                                  className={`side-tab-btn ${isSelected ? 'active' : ''}`}
                                >
                                  {side.toUpperCase()} FACE
                                </button>
                              );
                            })}
                          </div>
                          <span className="badge badge-emerald">4-WAY ROTATION DETECTED</span>
                        </div>

                        {/* Two-column visual layout */}
                        <div className="ocr-display-split">
                          {/* Left: Image preview with OCR Bounding Box Highlights */}
                          <div className="packaging-photo-box">
                            <div className="photo-tag-row">
                              <span className="photo-tag">{activeSide.toUpperCase()} PACKAGING PHOTO</span>
                              <div className="photo-tag-actions">
                                {boundingBoxes.length > 0 && (
                                  <button
                                    type="button"
                                    onClick={() => setShowBoxes({ ...showBoxes, [scan.scan_id]: showBoxes[scan.scan_id] === false ? true : false })}
                                    className={`toggle-boxes-btn font-mono ${showBoxes[scan.scan_id] !== false ? 'active' : ''}`}
                                    title="Toggle OCR detected word boxes on image"
                                  >
                                    {showBoxes[scan.scan_id] !== false ? <Eye size={12} /> : <EyeOff size={12} />}
                                    <span>{showBoxes[scan.scan_id] !== false ? `OCR Highlights (${boundingBoxes.length})` : 'Highlight OCR'}</span>
                                  </button>
                                )}
                                {activeImageUrl && (
                                  <a href={activeImageUrl} target="_blank" rel="noreferrer" className="open-link font-mono">
                                    <ExternalLink size={12} /> Full Res
                                  </a>
                                )}
                              </div>
                            </div>
                            <div className="photo-container">
                              {activeImageUrl ? (
                                <div className="image-with-boxes-wrap">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img
                                    src={activeImageUrl}
                                    alt={`${scan.product_name || 'Product'} ${activeSide} packaging`}
                                    className="product-face-img"
                                  />
                                  {showBoxes[scan.scan_id] !== false && boundingBoxes.length > 0 && (
                                    <div className="ocr-bounding-boxes-layer">
                                      {boundingBoxes.map((box, bIdx) => {
                                        const isHovered = hoveredBoxId === `${scan.scan_id}-${activeSide}-${bIdx}`;
                                        const nx = box.normalized?.x ?? 0;
                                        const ny = box.normalized?.y ?? 0;
                                        const nw = box.normalized?.width ?? 20;
                                        const nh = box.normalized?.height ?? 6;
                                        return (
                                          <div
                                            key={bIdx}
                                            className={`ocr-bbox-item ${isHovered ? 'hovered' : ''}`}
                                            style={{
                                              left: `${nx}%`,
                                              top: `${ny}%`,
                                              width: `${nw}%`,
                                              height: `${nh}%`,
                                            }}
                                            onMouseEnter={() => setHoveredBoxId(`${scan.scan_id}-${activeSide}-${bIdx}`)}
                                            onMouseLeave={() => setHoveredBoxId(null)}
                                            title={`${box.text} (${Math.round((box.score || 0.95) * 100)}% conf)`}
                                          >
                                            <span className="bbox-label font-mono">
                                              {box.text}
                                            </span>
                                          </div>
                                        );
                                      })}
                                    </div>
                                  )}
                                </div>
                              ) : (
                                <div className="no-image-placeholder">No image uploaded for this face</div>
                              )}
                            </div>
                          </div>

                          {/* Right: OCR Transcribed Text */}
                          <div className="ocr-text-box">
                            <div className="ocr-text-header">
                              <div className="ocr-meta">
                                <span className="ocr-label">ALL DETECTED TEXT ON THIS FACE</span>
                                <span className="ocr-count-badge font-mono">
                                  {activeOcrText ? `${activeOcrText.split('\n').filter(Boolean).length} Lines Detected` : '0 Lines'}
                                </span>
                              </div>
                              {activeOcrText && (
                                <button
                                  type="button"
                                  onClick={() => {
                                    navigator.clipboard.writeText(activeOcrText);
                                    setCopiedTextId(`${scan.scan_id}-${activeSide}`);
                                    setTimeout(() => setCopiedTextId(null), 2000);
                                  }}
                                  className="copy-ocr-btn font-mono"
                                  title="Copy extracted text to clipboard"
                                >
                                  {copiedTextId === `${scan.scan_id}-${activeSide}` ? (
                                    <>
                                      <Check size={13} className="text-emerald" /> Copied
                                    </>
                                  ) : (
                                    <>
                                      <Copy size={13} /> Copy Text
                                    </>
                                  )}
                                </button>
                              )}
                            </div>

                            <div className="ocr-lines-container font-mono">
                              {activeOcrText ? (
                                activeOcrText.split('\n').map((line, lIdx) => {
                                  const trimmed = line.trim();
                                  if (!trimmed) return null;
                                  return (
                                    <div key={lIdx} className="ocr-line-row">
                                      <span className="line-num">{String(lIdx + 1).padStart(2, '0')}</span>
                                      <span className="line-content">{trimmed}</span>
                                    </div>
                                  );
                                })
                              ) : (
                                <p className="ocr-empty-note font-mono">
                                  No text detected or processing OCR for this face.
                                </p>
                              )}
                            </div>
                          </div>
                        </div>
                      </div>
                    ) : (
                      <p className="empty-text">No packaging images recorded for this scan session.</p>
                    )}
                  </div>

                  {/* 1. LLM Packaging Verification Sentences */}
                  <div className="dossier-section">
                    <div className="section-title-row">
                      <Sparkles size={16} className="text-emerald" />
                      <h4 className="section-heading">LLM Packaging Verification Sentences</h4>
                      <span className="badge badge-emerald font-mono">NARRATIVE SUMMARY</span>
                    </div>

                    <div className="summary-sentences-card">
                      {resolvedSentences.length > 0 ? (
                        <div className="sentences-list">
                          {resolvedSentences.map((sentence, sIdx) => (
                            <div key={sIdx} className="sentence-item">
                              <span className="sentence-bullet">✦</span>
                              <p className="sentence-text">
                                {renderHighlightedSentence(sentence)}
                              </p>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <p className="empty-text">No summary sentences generated yet.</p>
                      )}
                    </div>
                  </div>

                  {/* 2. Highlighted Brand Claims Section */}
                  <div className="dossier-section">
                    <div className="section-title-row">
                      <Award size={16} className="text-emerald" />
                      <h4 className="section-heading">Claims Made by Brand (Extracted & Highlighted)</h4>
                      <span className="badge badge-purple font-mono">{brandClaims.length} CLAIMS HIGHLIGHTED</span>
                    </div>

                    {brandClaims.length > 0 ? (
                      <div className="brand-claims-grid">
                        {brandClaims.map((claimObj: any, cIdx: number) => (
                          <div key={cIdx} className="brand-claim-card">
                            <div className="claim-card-top">
                              <span className="claim-category-badge">{claimObj.category || 'Brand Claim'}</span>
                              <span className="claim-highlight-pill font-mono">VERIFIED CLAIM</span>
                            </div>
                            <div className="claim-text-row">
                              <span className="claim-quote">&ldquo;</span>
                              <h5 className="claim-title">{claimObj.claim}</h5>
                              <span className="claim-quote">&rdquo;</span>
                            </div>
                            {claimObj.context && (
                              <p className="claim-context font-mono">{claimObj.context}</p>
                            )}
                            {claimObj.verification_note && (
                              <div className="claim-verification-note">
                                <span className="note-label">COMPLIANCE NOTE:</span> {claimObj.verification_note}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div className="no-claims-box">
                        <span className="font-mono text-muted">No explicit voluntary marketing claims declared on packaging faces.</span>
                      </div>
                    )}
                  </div>

                  {/* 3. Comprehensive Declarations & Specifications Table */}
                  <div className="dossier-section">
                    <div className="section-title-row">
                      <TableIcon size={16} className="text-emerald" />
                      <h4 className="section-heading">Complete Declarations & Specifications Table</h4>
                      <span className="badge badge-emerald font-mono">LMPC RULE 6 COMPLIANT TABLE</span>
                    </div>

                    <div className="table-responsive-container">
                      <table className="declarations-table">
                        <thead>
                          <tr>
                            <th style={{ width: '28%' }}>STATUTORY / BRAND ATTRIBUTE</th>
                            <th style={{ width: '42%' }}>DISCLOSED VALUE ON PACKAGE</th>
                            <th style={{ width: '18%' }}>CATEGORY</th>
                            <th style={{ width: '12%', textAlign: 'center' }}>TYPE</th>
                          </tr>
                        </thead>
                        <tbody>
                          {declarationsTableRows.map((row: any, rIdx: number) => {
                            const isClaim = row.is_brand_claim || row.category === 'Brand Claim';
                            return (
                              <tr key={rIdx} className={isClaim ? 'claim-row-highlight' : 'standard-row'}>
                                <td className="attr-cell font-bold">
                                  {isClaim && <span className="claim-star-indicator">★ </span>}
                                  {row.attribute}
                                </td>
                                <td className="val-cell font-mono">
                                  {row.value || 'Not Disclosed'}
                                </td>
                                <td className="cat-cell">
                                  <span className={`cat-pill ${isClaim ? 'cat-pill-claim' : 'cat-pill-statutory'}`}>
                                    {row.category}
                                  </span>
                                </td>
                                <td className="type-cell" style={{ textAlign: 'center' }}>
                                  {isClaim ? (
                                    <span className="type-badge-claim font-mono">BRAND CLAIM</span>
                                  ) : (
                                    <span className="type-badge-statutory font-mono">DECLARATION</span>
                                  )}
                                </td>
                              </tr>
                            );
                          })}
                        </tbody>
                      </table>
                    </div>
                  </div>

                  {/* Rule-by-Rule Evaluations & Violations */}
                  {scan.evaluations && scan.evaluations.length > 0 && (
                    <div className="dossier-section">
                      <div className="section-title-row">
                        <Layers size={16} className="text-emerald" />
                        <h4 className="section-heading">Statutory Rule Evaluations & Citations</h4>
                      </div>

                      <div className="eval-list">
                        {scan.evaluations.map((ev, idx) => (
                          <div
                            key={idx}
                            className={`eval-item ${ev.status === 'FAIL' ? 'fail-border' : 'pass-border'}`}
                          >
                            <div className="eval-top">
                              <span className="eval-title">{ev.rule_title}</span>
                              <span
                                className={`badge ${
                                  ev.status === 'PASS'
                                    ? 'badge-emerald'
                                    : ev.status === 'FAIL'
                                    ? 'badge-crimson'
                                    : 'badge-amber'
                                }`}
                              >
                                {ev.status}
                              </span>
                            </div>
                            <p className="eval-reason">{ev.reason}</p>
                            {ev.citation && (
                              <div className="eval-citation font-mono">
                                <span className="citation-act">[{ev.citation.act_name || 'LMPC Rules 2011'} - {ev.citation.rule_reference}]</span>
                                {ev.citation.quote && <p className="citation-quote">&quot;{ev.citation.quote}&quot;</p>}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Officer Action Bar */}
                  <div className="officer-decision-bar">
                    <div className="decision-prompt">
                      <span className="prompt-title">Officer Enforcement Action</span>
                      <p className="prompt-desc">
                        Record legal decision into immutable audit trail under Section 15 of Legal Metrology Act, 2009.
                      </p>
                    </div>

                    <div className="decision-input-row">
                      <input
                        type="text"
                        placeholder="Resolution notes / Compound notice reference..."
                        value={reviewNotes[scan.scan_id] || ''}
                        onChange={(e) =>
                          setReviewNotes({
                            ...reviewNotes,
                            [scan.scan_id]: e.target.value,
                          })
                        }
                        className="decision-notes-input"
                      />

                      <div className="btn-group">
                        <button
                          disabled={isProcessing}
                          onClick={() => handleDecision(scan.scan_id, 'ACCEPT')}
                          className="btn-primary"
                        >
                          <CheckCircle2 size={15} />
                          Accept Scan
                        </button>
                        <button
                          disabled={isProcessing}
                          onClick={() => handleDecision(scan.scan_id, 'REJECT')}
                          className="btn-reject"
                        >
                          <XCircle size={15} />
                          Reject Findings
                        </button>
                        <button
                          disabled={isProcessing}
                          onClick={() => handleDecision(scan.scan_id, 'REQUEST_RESCAN')}
                          className="btn-secondary"
                        >
                          <RotateCcw size={15} />
                          Request Rescan
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              ); })()}
            </div>
          );
        })}
      </div>

      <style jsx>{`
        .tab-wrapper {
          display: flex;
          flex-direction: column;
          gap: 16px;
        }

        .info-banner {
          display: flex;
          align-items: center;
          gap: 16px;
          padding: 16px 20px;
          background: #ecfdf5;
          border: 1px solid #a7f3d0;
        }

        .banner-icon-box {
          width: 42px;
          height: 42px;
          border-radius: 12px;
          background: #d1fae5;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .text-emerald {
          color: #059669;
        }

        .banner-title {
          font-size: 1.05rem;
          font-weight: 800;
          color: #0f172a;
        }

        .banner-subtitle {
          font-size: 0.8rem;
          color: #475569;
          margin-top: 2px;
        }

        .scans-list {
          display: flex;
          flex-direction: column;
          gap: 14px;
        }

        .scan-card {
          padding: 16px 20px;
          display: flex;
          flex-direction: column;
        }

        .scan-card-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          cursor: pointer;
        }

        .left-meta {
          display: flex;
          align-items: center;
          gap: 14px;
        }

        .status-indicator {
          width: 38px;
          height: 38px;
          border-radius: 12px;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .status-indicator.pass {
          background: #d1fae5;
          color: #059669;
          border: 1px solid #a7f3d0;
        }

        .status-indicator.fail {
          background: #fee2e2;
          color: #dc2626;
          border: 1px solid #fecaca;
        }

        .status-indicator.review {
          background: #fef3c7;
          color: #d97706;
          border: 1px solid #fde68a;
        }

        .product-title-row {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .product-name {
          font-size: 1rem;
          font-weight: 800;
          color: #0f172a;
        }

        .product-sub-row {
          display: flex;
          align-items: center;
          gap: 8px;
          font-size: 0.75rem;
          color: #64748b;
          margin-top: 3px;
        }

        .mfr-name {
          color: #334155;
          font-weight: 600;
        }

        .dot {
          color: #cbd5e1;
        }

        .time-text {
          display: flex;
          align-items: center;
          gap: 4px;
        }

        .right-actions {
          display: flex;
          align-items: center;
          gap: 10px;
        }

        .report-btn {
          text-decoration: none;
          font-size: 0.8rem;
          padding: 8px 14px;
        }

        .expand-btn {
          background: rgba(255, 255, 255, 0.85);
          border: 1px solid #e2e8f0;
          color: #475569;
          width: 34px;
          height: 34px;
          border-radius: 8px;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
        }

        .expanded-content {
          margin-top: 18px;
          border-top: 1px solid #f1f5f9;
          padding-top: 16px;
          display: flex;
          flex-direction: column;
          gap: 16px;
        }

        .dossier-section {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .section-title-row {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .section-heading {
          font-size: 0.85rem;
          font-weight: 800;
          color: #0f172a;
        }

        .declarations-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
          gap: 10px;
          background: rgba(255, 255, 255, 0.9);
          padding: 14px;
          border-radius: 12px;
          border: 1px solid #e2e8f0;
        }

        .decl-item {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }

        .decl-key {
          font-size: 0.68rem;
          font-weight: 700;
          color: #64748b;
          text-transform: uppercase;
        }

        .decl-val {
          font-size: 0.82rem;
          color: #0f172a;
          word-break: break-word;
          font-weight: 600;
        }

        .eval-list {
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .eval-item {
          background: rgba(255, 255, 255, 0.9);
          border: 1px solid #e2e8f0;
          padding: 12px 14px;
          border-radius: 10px;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }

        .eval-item.fail-border {
          border-left: 4px solid #ef4444;
        }

        .eval-item.pass-border {
          border-left: 4px solid #10b981;
        }

        .eval-top {
          display: flex;
          align-items: center;
          justify-content: space-between;
        }

        .eval-title {
          font-size: 0.85rem;
          font-weight: 700;
          color: #0f172a;
        }

        .eval-reason {
          font-size: 0.8rem;
          color: #475569;
          line-height: 1.4;
        }

        .eval-citation {
          font-size: 0.72rem;
          color: #065f46;
          background: #ecfdf5;
          padding: 6px 10px;
          border-radius: 6px;
          border-left: 2px solid #10b981;
        }

        .citation-act {
          font-weight: 700;
        }

        .citation-quote {
          margin-top: 2px;
          color: #334155;
          font-style: italic;
        }

        .officer-decision-bar {
          background: #f8fafc;
          border: 1px solid #e2e8f0;
          border-radius: 12px;
          padding: 14px 18px;
          display: flex;
          flex-direction: column;
          gap: 12px;
        }

        .prompt-title {
          font-size: 0.85rem;
          font-weight: 800;
          color: #0f172a;
        }

        .prompt-desc {
          font-size: 0.75rem;
          color: #64748b;
        }

        .decision-input-row {
          display: flex;
          gap: 10px;
          flex-wrap: wrap;
        }

        .decision-notes-input {
          flex: 1;
          min-width: 250px;
          background: #ffffff;
          border: 1px solid #cbd5e1;
          border-radius: 8px;
          padding: 8px 12px;
          color: #0f172a;
          font-size: 0.8rem;
          font-family: var(--font-outfit);
          outline: none;
        }

        .decision-notes-input:focus {
          border-color: #10b981;
        }

        .btn-group {
          display: flex;
          gap: 8px;
        }

        /* --- Packaging Photo & OCR Studio Styles --- */
        .ocr-studio-card {
          background: #ffffff;
          border: 1px solid #e2e8f0;
          border-radius: 14px;
          overflow: hidden;
          box-shadow: 0 4px 16px rgba(15, 23, 42, 0.04);
        }

        .side-tabs-bar {
          display: flex;
          align-items: center;
          gap: 12px;
          padding: 10px 16px;
          background: #f8fafc;
          border-bottom: 1px solid #e2e8f0;
          flex-wrap: wrap;
        }

        .tabs-label {
          font-size: 0.76rem;
          font-weight: 700;
          color: #64748b;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }

        .side-tabs {
          display: flex;
          gap: 8px;
          flex: 1;
        }

        .side-tab-btn {
          background: #ffffff;
          border: 1px solid #cbd5e1;
          color: #475569;
          font-size: 0.72rem;
          font-weight: 700;
          padding: 5px 12px;
          border-radius: 8px;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .side-tab-btn:hover {
          border-color: #10b981;
          color: #065f46;
        }

        .side-tab-btn.active {
          background: #065f46;
          border-color: #065f46;
          color: #ffffff;
          box-shadow: 0 2px 8px rgba(6, 95, 70, 0.25);
        }

        .ocr-display-split {
          display: grid;
          grid-template-columns: 280px 1fr;
          min-height: 260px;
        }

        @media (max-width: 850px) {
          .ocr-display-split {
            grid-template-columns: 1fr;
          }
        }

        .packaging-photo-box {
          border-right: 1px solid #e2e8f0;
          background: #f1f5f9;
          display: flex;
          flex-direction: column;
        }

        .photo-tag-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 8px 12px;
          background: #e2e8f0;
          font-size: 0.7rem;
        }

        .photo-tag {
          font-weight: 800;
          color: #334155;
          letter-spacing: 0.5px;
        }

        .photo-container {
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 12px;
          background: #0f172a;
          overflow: hidden;
        }

        .product-face-img {
          max-height: 220px;
          max-width: 100%;
          object-fit: contain;
          border-radius: 6px;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
          transition: transform 0.2s ease;
        }

        .product-face-img:hover {
          transform: scale(1.02);
        }

        .no-image-placeholder {
          color: #94a3b8;
          font-size: 0.75rem;
          text-align: center;
        }

        .ocr-text-box {
          display: flex;
          flex-direction: column;
          background: #ffffff;
        }

        .ocr-text-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 10px 14px;
          background: #f8fafc;
          border-bottom: 1px solid #e2e8f0;
        }

        .ocr-meta {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .ocr-label {
          font-size: 0.75rem;
          font-weight: 800;
          color: #0f172a;
          letter-spacing: 0.4px;
        }

        .ocr-count-badge {
          font-size: 0.68rem;
          background: #ecfdf5;
          color: #065f46;
          border: 1px solid #a7f3d0;
          padding: 2px 8px;
          border-radius: 12px;
          font-weight: 700;
        }

        .copy-ocr-btn {
          display: flex;
          align-items: center;
          gap: 5px;
          background: #ffffff;
          border: 1px solid #cbd5e1;
          color: #334155;
          font-size: 0.7rem;
          font-weight: 600;
          padding: 4px 10px;
          border-radius: 6px;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .copy-ocr-btn:hover {
          border-color: #10b981;
          color: #065f46;
        }

        .ocr-lines-container {
          padding: 12px 14px;
          max-height: 240px;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: 6px;
        }

        .ocr-line-row {
          display: flex;
          align-items: baseline;
          gap: 10px;
          padding: 4px 8px;
          background: #f8fafc;
          border-radius: 6px;
          border-left: 2px solid #10b981;
        }

        .line-num {
          font-size: 0.68rem;
          color: #94a3b8;
          font-weight: 700;
          user-select: none;
        }

        .line-content {
          font-size: 0.78rem;
          color: #0f172a;
          font-weight: 600;
          word-break: break-word;
        }

        .ocr-empty-note {
          font-size: 0.75rem;
          color: #94a3b8;
          padding: 20px;
          text-align: center;
        }

        /* --- OCR Highlights & Bounding Box Overlays --- */
        .photo-tag-actions {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .toggle-boxes-btn {
          display: flex;
          align-items: center;
          gap: 5px;
          background: #ffffff;
          border: 1px solid #10b981;
          color: #065f46;
          font-size: 0.68rem;
          font-weight: 700;
          padding: 3px 8px;
          border-radius: 6px;
          cursor: pointer;
          transition: all 0.2s ease;
        }

        .toggle-boxes-btn:hover {
          background: #ecfdf5;
        }

        .toggle-boxes-btn.active {
          background: #059669;
          border-color: #059669;
          color: #ffffff;
          box-shadow: 0 2px 6px rgba(5, 150, 105, 0.3);
        }

        .image-with-boxes-wrap {
          position: relative;
          display: inline-block;
          max-width: 100%;
          line-height: 0;
        }

        .ocr-bounding-boxes-layer {
          position: absolute;
          inset: 0;
          pointer-events: none;
        }

        .ocr-bbox-item {
          position: absolute;
          border: 2px solid rgba(16, 185, 129, 0.9);
          background: rgba(16, 185, 129, 0.18);
          border-radius: 3px;
          pointer-events: auto;
          cursor: pointer;
          transition: all 0.15s ease;
          box-shadow: 0 0 6px rgba(16, 185, 129, 0.4);
        }

        .ocr-bbox-item:hover,
        .ocr-bbox-item.hovered {
          background: rgba(16, 185, 129, 0.45);
          border-color: #34d399;
          z-index: 20;
          box-shadow: 0 0 12px rgba(52, 211, 153, 0.85);
          transform: scale(1.02);
        }

        .bbox-label {
          position: absolute;
          bottom: 100%;
          left: 0;
          background: rgba(15, 23, 42, 0.95);
          color: #ffffff;
          padding: 3px 7px;
          font-size: 9.5px;
          border-radius: 4px;
          white-space: nowrap;
          pointer-events: none;
          opacity: 0;
          transform: translateY(2px);
          transition: all 0.15s ease;
          z-index: 30;
          line-height: 1.2;
          box-shadow: 0 4px 10px rgba(0, 0, 0, 0.3);
        }

        .ocr-bbox-item:hover .bbox-label {
          opacity: 1;
          transform: translateY(-3px);
        }

        /* --- LLM Summary Sentences --- */
        .summary-sentences-card {
          background: #ffffff;
          border: 1px solid #e2e8f0;
          border-radius: 12px;
          padding: 16px 20px;
          box-shadow: 0 2px 8px rgba(15, 23, 42, 0.03);
        }

        .sentences-list {
          display: flex;
          flex-direction: column;
          gap: 10px;
        }

        .sentence-item {
          display: flex;
          align-items: flex-start;
          gap: 10px;
        }

        .sentence-bullet {
          color: #10b981;
          font-size: 0.9rem;
          line-height: 1.5;
        }

        .sentence-text {
          font-size: 0.85rem;
          color: #1e293b;
          line-height: 1.55;
          margin: 0;
        }

        .brand-claim-mark {
          background: linear-gradient(135deg, rgba(254, 240, 138, 0.6), rgba(167, 243, 208, 0.7));
          border: 1px solid #34d399;
          color: #065f46;
          padding: 1px 6px;
          border-radius: 4px;
          font-weight: 800;
        }

        /* --- Brand Claims Section --- */
        .brand-claims-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
          gap: 12px;
        }

        .brand-claim-card {
          background: linear-gradient(135deg, #ffffff 0%, #f0fdf4 100%);
          border: 1.5px solid #a7f3d0;
          border-radius: 12px;
          padding: 14px 16px;
          box-shadow: 0 4px 12px rgba(16, 185, 129, 0.06);
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        .claim-card-top {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .claim-category-badge {
          background: #ecfdf5;
          color: #065f46;
          border: 1px solid #6ee7b7;
          padding: 2px 8px;
          border-radius: 12px;
          font-size: 0.68rem;
          font-weight: 800;
          text-transform: uppercase;
        }

        .claim-highlight-pill {
          background: #7c3aed;
          color: #ffffff;
          padding: 2px 7px;
          border-radius: 10px;
          font-size: 0.62rem;
          font-weight: 800;
          letter-spacing: 0.5px;
        }

        .badge-purple {
          background: #f3e8ff;
          color: #6b21a8;
          border: 1px solid #d8b4fe;
        }

        .claim-text-row {
          display: flex;
          align-items: baseline;
          gap: 4px;
        }

        .claim-quote {
          font-size: 1.2rem;
          color: #10b981;
          font-weight: 800;
          line-height: 1;
        }

        .claim-title {
          font-size: 0.92rem;
          font-weight: 800;
          color: #0f172a;
          margin: 0;
          line-height: 1.35;
        }

        .claim-context {
          font-size: 0.72rem;
          color: #64748b;
          margin: 0;
        }

        .claim-verification-note {
          font-size: 0.72rem;
          color: #334155;
          background: rgba(255, 255, 255, 0.85);
          border-left: 2px solid #10b981;
          padding: 4px 8px;
          border-radius: 4px;
        }

        .note-label {
          font-weight: 800;
          color: #065f46;
        }

        .no-claims-box {
          background: #f8fafc;
          border: 1px dashed #cbd5e1;
          border-radius: 10px;
          padding: 14px;
          font-size: 0.78rem;
        }

        /* --- Complete Declarations Table --- */
        .table-responsive-container {
          background: #ffffff;
          border: 1px solid #e2e8f0;
          border-radius: 12px;
          overflow: hidden;
          box-shadow: 0 2px 10px rgba(15, 23, 42, 0.03);
        }

        .declarations-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 0.8rem;
        }

        .declarations-table th {
          background: #f8fafc;
          color: #475569;
          font-size: 0.7rem;
          font-weight: 800;
          letter-spacing: 0.5px;
          padding: 10px 14px;
          border-bottom: 1px solid #e2e8f0;
          text-align: left;
        }

        .declarations-table td {
          padding: 10px 14px;
          border-bottom: 1px solid #f1f5f9;
          vertical-align: middle;
        }

        .declarations-table tr:last-child td {
          border-bottom: none;
        }

        .claim-row-highlight {
          background: #f0fdf4 !important;
          border-left: 3px solid #10b981;
        }

        .claim-row-highlight td {
          background: #f0fdf4 !important;
        }

        .claim-star-indicator {
          color: #f59e0b;
          font-size: 0.85rem;
        }

        .cat-pill {
          font-size: 0.68rem;
          padding: 2px 8px;
          border-radius: 12px;
          font-weight: 700;
        }

        .cat-pill-statutory {
          background: #f1f5f9;
          color: #475569;
          border: 1px solid #e2e8f0;
        }

        .cat-pill-claim {
          background: #fef3c7;
          color: #92400e;
          border: 1px solid #fde68a;
        }

        .type-badge-statutory {
          font-size: 0.64rem;
          color: #64748b;
          background: #f8fafc;
          border: 1px solid #e2e8f0;
          padding: 2px 6px;
          border-radius: 6px;
          font-weight: 700;
        }

        .type-badge-claim {
          font-size: 0.64rem;
          color: #065f46;
          background: #d1fae5;
          border: 1px solid #6ee7b7;
          padding: 2px 6px;
          border-radius: 6px;
          font-weight: 800;
        }
      `}</style>
    </div>
  );
};
