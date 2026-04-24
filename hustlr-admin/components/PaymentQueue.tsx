'use client';
import { useState, useEffect } from 'react';
import { CreditCard, Search, Filter, MoreHorizontal, CheckCircle, RefreshCw, AlertCircle } from 'lucide-react';
import AdminApiService from '@/lib/api-service';
import type { PayoutRequest } from '@/lib/mock-data';

export default function PaymentQueue() {
  const [payouts, setPayouts] = useState<PayoutRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('APPROVED');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPayout, setSelectedPayout] = useState<PayoutRequest | null>(null);
  const [processDialogOpen, setProcessDialogOpen] = useState(false);
  const [paymentMethod, setPaymentMethod] = useState('UPI');
  const [upiRef, setUpiRef] = useState('');

  useEffect(() => {
    loadPayouts();
  }, [statusFilter]);

  const loadPayouts = async () => {
    setLoading(true);
    try {
      const data = await AdminApiService.getPayoutQueue({ status: statusFilter });
      setPayouts(data);
      setLoading(false);
    } catch (e) {
      setLoading(false);
    }
  };

  const handleProcessPayment = async (payoutId: string) => {
    const success = await AdminApiService.processPayout(payoutId, paymentMethod, upiRef);
    if (success) {
      loadPayouts();
      setProcessDialogOpen(false);
      setSelectedPayout(null);
      setUpiRef('');
    }
  };

  const handleRetryPayment = async (payoutId: string) => {
    setProcessDialogOpen(true);
    setSelectedPayout(payouts.find(p => p.id === payoutId) || null);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'APPROVED': return 'green';
      case 'PENDING': return 'orange';
      case 'PROCESSING': return 'blue';
      case 'FAILED': return 'red';
      default: return 'gray';
    }
  };

  const safePayouts = Array.isArray(payouts) ? payouts : [];

  const filteredPayouts = safePayouts.filter(
    (payout) =>
      payout.userName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      payout.userPhone.includes(searchQuery) ||
      payout.claimId.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const formatDate = (date: Date) => {
    return new Date(date).toLocaleDateString('en-IN', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-white">Payment Queue</h2>
        <div className="flex items-center gap-2">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search payouts..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8 pr-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
            />
          </div>
          <div className="flex items-center gap-1 bg-gray-700 rounded-lg p-1">
            {['APPROVED', 'PENDING', 'PROCESSING', 'FAILED'].map((status) => (
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
          <CreditCard className="w-8 h-8 text-green-500 animate-spin mx-auto mb-2" />
          <p className="text-gray-400">Loading payouts...</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-left text-gray-400 text-xs uppercase border-b border-gray-700">
                <th className="pb-3 font-medium">Payout ID</th>
                <th className="pb-3 font-medium">User</th>
                <th className="pb-3 font-medium">Amount</th>
                <th className="pb-3 font-medium">Method</th>
                <th className="pb-3 font-medium">Status</th>
                <th className="pb-3 font-medium">Created</th>
                <th className="pb-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredPayouts.map((payout) => (
                <tr key={payout.id} className="border-b border-gray-700/50 hover:bg-gray-700/30">
                  <td className="py-3 text-sm text-gray-300">{payout.id}</td>
                  <td className="py-3">
                    <div>
                      <p className="text-sm font-medium text-white">{payout.userName}</p>
                      <p className="text-xs text-gray-400">{payout.userPhone}</p>
                    </div>
                  </td>
                  <td className="py-3">
                    <span className="text-sm font-bold text-green-500">₹{payout.amount.toFixed(0)}</span>
                  </td>
                  <td className="py-3 text-sm text-gray-300">{payout.paymentMethod}</td>
                  <td className="py-3">
                    <span
                      className={`px-2 py-1 text-xs font-bold rounded bg-${getStatusColor(payout.status)}-500/10 text-${getStatusColor(payout.status)}-500 border border-${getStatusColor(payout.status)}-500`}
                    >
                      {payout.status}
                    </span>
                  </td>
                  <td className="py-3 text-sm text-gray-300">{formatDate(payout.createdAt)}</td>
                  <td className="py-3">
                    <button
                      onClick={() => setSelectedPayout(payout)}
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

      {selectedPayout && !processDialogOpen && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-lg w-full mx-4 border border-gray-700">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold text-white">Payout Details</h3>
              <button
                onClick={() => setSelectedPayout(null)}
                className="p-1 text-gray-400 hover:text-white"
              >
                <MoreHorizontal className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-gray-400 uppercase">Payout ID</p>
                  <p className="text-sm font-medium text-white">{selectedPayout.id}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Claim ID</p>
                  <p className="text-sm font-medium text-white">{selectedPayout.claimId}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">User</p>
                  <p className="text-sm font-medium text-white">{selectedPayout.userName}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Phone</p>
                  <p className="text-sm font-medium text-white">{selectedPayout.userPhone}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Amount</p>
                  <p className="text-sm font-bold text-green-500">₹{selectedPayout.amount.toFixed(0)}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Payment Method</p>
                  <p className="text-sm font-medium text-white">{selectedPayout.paymentMethod}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Status</p>
                  <span
                    className={`px-2 py-1 text-xs font-bold rounded bg-${getStatusColor(selectedPayout.status)}-500/10 text-${getStatusColor(selectedPayout.status)}-500 border border-${getStatusColor(selectedPayout.status)}-500`}
                  >
                    {selectedPayout.status}
                  </span>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Created</p>
                  <p className="text-sm font-medium text-white">{formatDate(selectedPayout.createdAt)}</p>
                </div>
              </div>

              {selectedPayout.upiRef && (
                <div>
                  <p className="text-xs text-gray-400 uppercase">UPI Reference</p>
                  <p className="text-sm font-medium text-white">{selectedPayout.upiRef}</p>
                </div>
              )}

              {selectedPayout.processedAt && (
                <div>
                  <p className="text-xs text-gray-400 uppercase">Processed At</p>
                  <p className="text-sm font-medium text-white">{formatDate(selectedPayout.processedAt)}</p>
                </div>
              )}

              <div className="flex gap-2 pt-4 border-t border-gray-700">
                {selectedPayout.status === 'APPROVED' && (
                  <button
                    onClick={() => {
                      setProcessDialogOpen(true);
                      setPaymentMethod(selectedPayout.paymentMethod);
                    }}
                    className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600"
                  >
                    <CheckCircle className="w-4 h-4" />
                    Process Payment
                  </button>
                )}
                {selectedPayout.status === 'FAILED' && (
                  <button
                    onClick={() => handleRetryPayment(selectedPayout.id)}
                    className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600"
                  >
                    <RefreshCw className="w-4 h-4" />
                    Retry Payment
                  </button>
                )}
                <button
                  onClick={() => setSelectedPayout(null)}
                  className="flex-1 px-4 py-2 bg-gray-700 text-white rounded-lg hover:bg-gray-600"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {processDialogOpen && selectedPayout && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-lg w-full mx-4 border border-gray-700">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold text-white">Process Payment</h3>
              <button
                onClick={() => {
                  setProcessDialogOpen(false);
                  setUpiRef('');
                }}
                className="p-1 text-gray-400 hover:text-white"
              >
                <MoreHorizontal className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div className="bg-gray-700/50 rounded-lg p-4">
                <div className="flex justify-between mb-2">
                  <span className="text-gray-400">Amount</span>
                  <span className="text-lg font-bold text-green-500">₹{selectedPayout.amount.toFixed(0)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">User</span>
                  <span className="text-white">{selectedPayout.userName}</span>
                </div>
              </div>

              <div>
                <p className="text-xs text-gray-400 uppercase mb-2">Payment Method</p>
                <div className="flex gap-2">
                  {['UPI', 'Wallet'].map((method) => (
                    <button
                      key={method}
                      onClick={() => setPaymentMethod(method)}
                      className={`flex-1 px-4 py-2 rounded-lg ${
                        paymentMethod === method
                          ? 'bg-green-500 text-white'
                          : 'bg-gray-700 text-gray-400 hover:bg-gray-600'
                      }`}
                    >
                      {method}
                    </button>
                  ))}
                </div>
              </div>

              {paymentMethod === 'UPI' && (
                <div>
                  <p className="text-xs text-gray-400 uppercase mb-2">UPI Reference</p>
                  <input
                    type="text"
                    value={upiRef}
                    onChange={(e) => setUpiRef(e.target.value)}
                    placeholder="Enter UPI reference..."
                    className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
                  />
                </div>
              )}

              <div className="flex gap-2 pt-4">
                <button
                  onClick={() => handleProcessPayment(selectedPayout.id)}
                  className="flex-1 flex items-center justify-center gap-2 px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600"
                >
                  <CheckCircle className="w-4 h-4" />
                  Confirm Payment
                </button>
                <button
                  onClick={() => {
                    setProcessDialogOpen(false);
                    setUpiRef('');
                  }}
                  className="flex-1 px-4 py-2 bg-gray-700 text-white rounded-lg hover:bg-gray-600"
                >
                  Cancel
                </button>
              </div>

              {paymentMethod === 'UPI' && !upiRef && (
                <div className="flex items-center gap-2 text-orange-500 bg-orange-500/10 rounded-lg p-3">
                  <AlertCircle className="w-4 h-4" />
                  <p className="text-xs">UPI reference is required for UPI payments</p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
