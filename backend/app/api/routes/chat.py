"""
NIRIKSHAK AI - RAG-Powered Legal Metrology Chatbot API Routes.
"""

from typing import Any, Dict, List, Optional
from fastapi import APIRouter
from pydantic import BaseModel
from groq import Groq

from app.core.config import get_settings
from app.core.logging import get_logger
from app.services.rag.rag_pipeline import RAGPipeline
from app.services.rag.violation_analyzer import STATUTORY_DEFAULTS

logger = get_logger("routes.chat")
settings = get_settings()

router = APIRouter(prefix="/chat", tags=["RAG Chatbot"])
rag_pipeline = RAGPipeline()


class ChatRequest(BaseModel):
    message: str
    rule_id: Optional[str] = None
    context: Optional[str] = None


@router.post("")
async def chat_with_legal_bot(request: ChatRequest) -> Dict[str, Any]:
    """
    RAG-powered conversational Legal Assistant for the Legal Metrology Act, 2009
    and Legal Metrology (Packaged Commodities) Rules, 2011.
    """
    user_query = request.message.strip()

    # 1. Retrieve relevant statutory context from ChromaDB
    # Use user query directly for optimal vector semantic similarity
    retrieval_query = user_query
    if request.rule_id and request.rule_id.lower() not in user_query.lower():
        retrieval_query = f"{user_query} {request.rule_id}"

    context = rag_pipeline.search_legal_context(
        query=retrieval_query,
        top_k=5,
        rule_id_filter=request.rule_id,
    )

    retrieved_docs = context.get("retrieved_documents", [])
    citations: List[Dict[str, str]] = []
    context_text_snippets = []

    for i, doc in enumerate(retrieved_docs, 1):
        content = doc.get("content") or doc.get("text", "")
        metadata = doc.get("metadata", {})
        doc_name = metadata.get("document_name", "Legal Metrology Authority")
        rule_ref = metadata.get("rule_id") or metadata.get("rule_reference", "LMPC Law")

        citations.append({
            "citation_id": f"[{i}]",
            "document": doc_name,
            "rule": rule_ref,
            "excerpt": content[:220].strip() + "..." if len(content) > 220 else content.strip(),
        })
        context_text_snippets.append(f"[{i}] Document: {doc_name} (Reference: {rule_ref})\n{content}")

    # If a statutory default exists for the rule_id, include it
    statutory_note = ""
    if request.rule_id and request.rule_id in STATUTORY_DEFAULTS:
        sd = STATUTORY_DEFAULTS[request.rule_id]
        statutory_note = (
            f"\nOfficial Statutory Standard for {request.rule_id} ({sd.get('rule_code')}):\n"
            f"Statutory Provision: {sd.get('legal_quote')}\n"
            f"Non-Compliance Standard: {sd.get('reason')}\n"
            f"Statutory Penalty: {sd.get('penalty')}"
        )

    full_context_str = "\n\n".join(context_text_snippets) + statutory_note

    # 2. Generate Grounded Answer via Groq LLM
    final_reply = None
    if settings.groq_api_key and settings.groq_api_key != "your_groq_api_key_here":
        try:
            client = Groq(api_key=settings.groq_api_key)
            system_prompt = (
                "You are Nirikshak AI Legal Counsel, an authoritative, rigorous legal advisor specializing in "
                "the Legal Metrology Act, 2009 and the Legal Metrology (Packaged Commodities) Rules, 2011 (LMPC Rules).\n"
                "Your objective is to provide precise, legally grounded answers to citizens, enforcement officers, and businesses.\n\n"
                "MANDATORY GUIDELINES:\n"
                "1. Direct Answer: Answer the user's specific question directly in the first paragraph.\n"
                "2. Specific Provisions: Cite exact Rules and Sections (e.g., Rule 6(1)(a)-(g), Rule 18(2), Section 36(1), Section 15).\n"
                "3. Grounding in Citations: Utilize the provided official Legal Metrology documents and statutory chunks. Reference them where appropriate.\n"
                "4. Penalties & Enforcement: Always specify exact penalties under Section 36 of the Legal Metrology Act, 2009 "
                "(first offence: fine up to ₹25,000; second offence: up to ₹50,000; subsequent offences: up to ₹1,00,000 or imprisonment up to 1 year; "
                "goods liable to seizure under Section 15).\n"
                "5. Redressal: If the question involves consumer violations (such as overcharging or missing declarations), state how the consumer can file a complaint with the National Consumer Helpline (NCH 1915) or the State Legal Metrology Controller.\n"
                "6. Format cleanly using Markdown with bold highlights and bullet points. Never provide vague or generic disclaimers."
            )

            user_prompt = f"""User Question:
{user_query}

{f'Active Violation Context: {request.context}' if request.context else ''}

Retrieved Legal Metrology Statutory Chunks & Documents:
{full_context_str if full_context_str.strip() else 'Apply authoritative provisions of the Legal Metrology Act, 2009 and Legal Metrology (Packaged Commodities) Rules, 2011.'}
"""
            candidate_models = [
                "qwen/qwen3.8-27b",
                settings.llm_model,
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
            ]
            models_to_try = [m for m in dict.fromkeys(candidate_models) if m]

            for model_name in models_to_try:
                try:
                    completion = client.chat.completions.create(
                        model=model_name,
                        messages=[
                            {"role": "system", "content": system_prompt},
                            {"role": "user", "content": user_prompt},
                        ],
                        temperature=0.15,
                        max_tokens=900,
                    )
                    content = completion.choices[0].message.content
                    if content and len(content.strip()) > 30:
                        final_reply = content
                        logger.info(f"Groq LLM response generated using model: {model_name}")
                        break
                except Exception as model_err:
                    logger.warning(f"Groq model {model_name} failed: {model_err}")

        except Exception as e:
            logger.error(f"Groq LLM chat completion failed entirely: {e}")

    # Fallback response if LLM was unavailable
    if not final_reply:
        if citations:
            reply_lines = [
                f"### Legal Metrology Regulatory Assessment\n",
                f"Regarding your query on **{user_query}**, the Legal Metrology Act, 2009 and Packaged Commodities Rules, 2011 establish the following statutory requirements:\n",
            ]
            for c in citations:
                reply_lines.append(f"- **{c['rule']}** ({c['document']}):\n  {c['excerpt']}\n")

            reply_lines.append("\n**Statutory Penalties (Section 36, Legal Metrology Act, 2009):**")
            reply_lines.append("• First Offence: Fine up to ₹25,000\n• Second Offence: Fine up to ₹50,000\n• Subsequent Offences: Up to ₹1,00,000 or imprisonment up to one year, with goods subject to seizure under Section 15.")
            final_reply = "\n".join(reply_lines)
        else:
            final_reply = (
                f"### Legal Metrology Act, 2009 Guidance on {user_query}\n\n"
                "Under the Legal Metrology (Packaged Commodities) Rules, 2011, pre-packaged commodities must strictly "
                "comply with mandatory label disclosures including generic name, net quantity in standard metric units, "
                "Maximum Retail Price (MRP inclusive of all taxes), complete manufacturer/packer address, date of manufacture/packing, "
                "and consumer grievance details.\n\n"
                "**Penalties for Violation:** Under Section 36(1) of the Act, non-compliant packaging or overcharging attracts "
                "a fine of up to ₹25,000 for the first offence, escalating to ₹50,000 for a second offence, and up to ₹1,00,000 or imprisonment for subsequent violations."
            )

    # Contextual suggested follow-ups
    suggested_followups = [
        "What is the penalty for MRP overcharging under Rule 18(2)?",
        "What are the mandatory declarations under Rule 6(1)?",
        "How can a citizen report an unlabelled or misleading package?",
        "What font size and unit symbols are legally required for Net Quantity?",
    ]

    return {
        "reply": final_reply,
        "citations": citations,
        "suggested_followups": suggested_followups,
        "rule_id": request.rule_id,
    }
