package com.klerp.fi.account.document.head;

/**
 * 模拟业务代码仓 — 与 SDD capability account-document-head-create 对齐。
 * CI 中 GitNexus / git diff 映射到本路径。
 */
public class AccountDocumentHeadService {

    public void validateRequiredFields(AccountDocumentHead head) {
        if (head.getDocumentDate() == null) {
            throw new BusinessException("凭证日期不能为空");
        }
        if (head.getPostingDate() == null) {
            throw new BusinessException("过账日期不能为空");
        }
    }

    public void calculateExchangeRate(AccountDocumentHead head) {
        // 实现需与 SDD 当前有效规则一致（由 opsx-kb-gitnexus-verify 比对）
    }
}
// github-pr-loop-20260614191815
