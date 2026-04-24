'use client';
import { useState, useEffect } from 'react';
import { Shield, Search, Filter, MoreHorizontal, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';
import AdminApiService from '@/lib/api-service';
import type { FraudCase } from '@/lib/mock-data';

export default function FraudQueue() {
  const [fraudCases, setFraudCases] = useState<FraudCase[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('FLAGGED');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCase, setSelectedCase] = useState<FraudCase | null>(null);

  useEffect(() => {
    loadFraudQueue();
  }, [statusFilter]);

  const loadFraudQueue = async () => {
    setLoading(true);
    try {
      const data = await AdminApiService.getFraudQueue({ status: statusFilter });
      setFraudCases(data);
      setLoading(false);
    } catch (e) {
      setLoading(false);
    }
  };

  const handleStatusUpdate = async (claimId: string, newStatus: string) => {
    const success = await AdminApiService.updateFraudStatus(claimId, newStatus);
    if (success) {
      loadFraudQueue();
      setSelectedCase(null);
    }
  };

  const getSeverityColor = (severity: number) => {
    if (severity >= 8) return 'red';
    if (severity >= 5) return 'orange';
    return 'yellow';
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'FLAGGED': return 'red';
      case 'REVIEW': return 'orange';
      case 'CLEAN': return 'green';
      case 'REJECTED': return 'gray';
      default: return 'gray';
    }
  };

  const filteredCases = fraudCases.filter(
    (caseItem) =>
      caseItem.userName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      caseItem.userPhone.includes(searchQuery) ||
      caseItem.policyId.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-white">Fraud Queue</h2>
        <div className="flex items-center gap-2">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8 pr-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
            />
          </div>
          <div className="flex items-center gap-1 bg-gray-700 rounded-lg p-1">
            {['FLAGGED', 'REVIEW', 'CLEAN', 'REJECTED'].map((status) => (
              <button
                key={status}
                onClick={() => setStatusFilter(status)}
                className={`px-3 py-1 text-xs font-bold rounded ${
                  statusFilter === status
                    ? 'bg-green-500 text-white'
                    : 'text-gray-400 hover:text-white'
                }`}
              >
                {status}
              </button>
            ))}
          </div>
        </div>
      </div>

      {loading ? (
        <div className="text-center py-8">
          <Shield className="w-8 h-8 text-green-500 animate-spin mx-auto mb-2" />
          <p className="text-gray-400">Loading fraud queue...</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-left text-gray-400 text-xs uppercase border-b border-gray-700">
                <th className="pb-3 font-medium">Claim ID</th>
                <th className="pb-3 font-medium">User</th>
                <th className="pb-3 font-medium">Zone</th>
                <th className="pb-3 font-medium">Score</th>
                <th className="pb-3 font-medium">Status</th>
                <th className="pb-3 font-medium">Severity</th>
                <th className="pb-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredCases.map((caseItem) => (
                <tr key={caseItem.id} className="border-b border-gray-700/50 hover:bg-gray-700/30">
                  <td className="py-3 text-sm text-gray-300">{caseItem.id}</td>
                  <td className="py-3">
                    <div>
                      <p className="text-sm font-medium text-white">{caseItem.userName}</p>
                      <p className="text-xs text-gray-400">{caseItem.userPhone}</p>
                    </div>
                  </td>
                  <td className="py-3 text-sm text-gray-300">{caseItem.zone}</td>
                  <td className="py-3 text-sm text-gray-300">{caseItem.fraudScore}</td>
                  <td className="py-3">
                    <span
                      className={`px-2 py-1 text-xs font-bold rounded bg-${getStatusColor(caseItem.fraudStatus)}-500/10 text-${getStatusColor(caseItem.fraudStatus)}-500 border border-${getStatusColor(caseItem.fraudStatus)}-500`}
                    >
                      {caseItem.fraudStatus}
                    </span>
                  </td>
                  <td className="py-3">
                    <div className="flex items-center gap-2">
                      <div className="w-16 h-2 bg-gray-700 rounded-full overflow-hidden">
                        <div
                          className={`h-full bg-${getSeverityColor(caseItem.severity)}-500`}
                          style={{ width: `${caseItem.severity * 10}%` }}
                        />
                      </div>
                      <span className="text-sm text-gray-300">{caseItem.severity}</span>
                    </div>
                  </td>
                  <td className="py-3">
                    <button
                      onClick={() => setSelectedCase(caseItem)}
                      className="p-1 text-gray-400 hover:text-white"
                    >
                      <MoreHorizontal className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {selectedCase && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto border border-gray-700">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold text-white">Fraud Case Details</h3>
              <button
                onClick={() => setSelectedCase(null)}
                className="p-1 text-gray-400 hover:text-white"
              >
                <XCircle className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-gray-400 uppercase">Claim ID</p>
                  <p className="text-sm font-medium text-white">{selectedCase.id}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Fraud Score</p>
                  <p className="text-sm font-medium text-white">{selectedCase.fraudScore}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">User</p>
                  <p className="text-sm font-medium text-white">{selectedCase.userName}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Phone</p>
                  <p className="text-sm font-medium text-white">{selectedCase.userPhone}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Trust Score</p>
                  <p className="text-sm font-medium text-white">{selectedCase.trustScore}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Trust Tier</p>
                  <p className="text-sm font-medium text-white">{selectedCase.trustTier}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Zone</p>
                  <p className="text-sm font-medium text-white">{selectedCase.zone}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Payout</p>
                  <p className="text-sm font-medium text-white">₹{selectedCase.grossPayout.toFixed(0)}</p>
                </div>
              </div>

              <div>
                <p className="text-xs text-gray-400 uppercase mb-2">Fraud Signals</p>
                <div className="space-y-2">
                  {selectedCase.fraudSignals.map((signal, index) => (
                    <div key={index} className="flex items-center justify-between bg-gray-700/50 rounded-lg p-2">
                      <div className="flex items-center gap-2">
                        <AlertTriangle className="w-4 h-4 text-orange-500" />
                        <span className="text-sm text-white">{signal.name}</span>
                      </div>
                      <div className="flex items-center gap-4">
                        <span className="text-xs text-gray-400">Value: {signal.value.toFixed(2)}</span>
                        <span className="text-xs text-gray-400">Weight: {signal.weight}</span>
                        <span className="text-xs font-bold text-orange-500">{signal.contribution}%</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div>
                <p className="text-xs text-gray-400 uppercase mb-2">Reason</p>
                <p className="text-sm text-white bg-gray-700/50 rounded-lg p-3">{selectedCase.reason}</p>
              </div>

              <div className="flex gap-2 pt-4 border-t border-gray-700">
                {selectedCase.fraudStatus === 'FLAGGED' || selectedCase.fraudStatus === 'REVIEW' ? (
                  <>
                    <button
                      onClick={() => handleStatusUpdate(selectedCase.id, 'CLEAN')}
                      className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600"
                    >
                      <CheckCircle className="w-4 h-4" />
                      Mark Clean
                    </button>
                    <button
                      onClick={() => handleStatusUpdate(selectedCase.id, 'REJECTED')}
                      className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600"
                    >
                      <XCircle className="w-4 h-4" />
                      Reject
                    </button>
                  </>
                ) : (
                  <p className="text-sm text-gray-400">This case has been {selectedCase.fraudStatus.toLowerCase()}</p>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
